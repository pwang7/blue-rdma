import FIFOF :: *;
import PAClib :: *;
import Vector :: *;

import Assertions :: *;
import Headers :: *;
import Controller :: *;
import DataTypes :: *;
import PrimUtils :: *;
import Settings :: *;
import Utils :: *;
import Utils4Test :: *;
import WorkCompGenRQ :: *;

(* synthesize *)
module mkTestWorkCompGenNormalCaseRQ(Empty);
    let isNormalCase = True;
    let result <- mkTestWorkCompGenRQ(isNormalCase);
endmodule

(* synthesize *)
module mkTestWorkCompGenErrFlushCaseRQ(Empty);
    let isNormalCase = False;
    let result <- mkTestWorkCompGenRQ(isNormalCase);
endmodule

module mkTestWorkCompGenRQ#(Bool isNormalCase)(Empty);
    let minPayloadLen = 1;
    let maxPayloadLen = 8192;
    let qpType = IBV_QPT_XRC_SEND;
    let pmtu = IBV_MTU_512;

    // WorkReq generation
    Vector#(1, PipeOut#(WorkReq)) workReqPipeOutVec <- mkRandomWorkReq(
        minPayloadLen, maxPayloadLen
    );
    let cntrl4PendingWR <- mkSimController(qpType, pmtu);
    Vector#(1, PipeOut#(PendingWorkReq)) pendingWorkReqPipeOutVec <-
        mkExistingPendingWorkReqPipeOut(cntrl4PendingWR, workReqPipeOutVec[0]);

    let pendingWorkReqPipeOut = pendingWorkReqPipeOutVec[0];

    // RecvReq
    FIFOF#(RecvReq) recvReqQ <- mkFIFOF;

    // PayloadConResp
    FIFOF#(PayloadConResp) payloadConRespQ <- mkFIFOF;

    // WC requests
    FIFOF#(WorkCompGenReqRQ) workCompGenReqQ4RQ <- mkFIFOF;

    let cntrl <- mkSimController(qpType, pmtu);
    // DUT
    let dut <- mkWorkCompGenRQ(
        cntrl,
        convertFifo2PipeOut(payloadConRespQ),
        convertFifo2PipeOut(workCompGenReqQ4RQ)
    );

    // RecvReq ID
    PipeOut#(WorkReqID) recvReqIdPipeOut <- mkGenericRandomPipeOut;

    // Expected WC
    FIFOF#(Tuple5#(
        WorkReqID, WorkCompOpCode, WorkCompFlags, Maybe#(IMM), Maybe#(RKEY)
    )) expectedWorkCompQ <- mkFIFOF;

    let countDown <- mkCountDown(valueOf(MAX_CMP_CNT));

    rule setCntrlErrState if (cntrl.isRTS);
        let wcStatus = dut.workCompStatusPipeOutRQ.first;
        dut.workCompStatusPipeOutRQ.deq;

        dynAssert(
            wcStatus != IBV_WC_SUCCESS,
            "wcStatus assertion @ mkTestWorkCompGenRQ",
            $format("wcStatus=", fshow(wcStatus), " should not be success")
        );
        cntrl.setStateErr;
    endrule

    rule genWorkCompReq4RQ;
        let pendingWR = pendingWorkReqPipeOut.first;
        pendingWorkReqPipeOut.deq;

        let hasImmDt   = isValid(pendingWR.wr.immDt);
        let hasIETH    = isValid(pendingWR.wr.rkey2Inv);
        let isZeroLen  = isZero(pendingWR.wr.len);

        let maybeImmDt     = pendingWR.wr.immDt;
        let maybeRKey2Inv  = pendingWR.wr.rkey2Inv;
        let maybeRecvReqID = tagged Invalid;
        if (workReqNeedRecvReq(pendingWR.wr.opcode)) begin
            let endPSN = unwrapMaybe(pendingWR.endPSN);
            if (!isZeroLen) begin
                let payloadConResp = PayloadConResp {
                    initiator: dontCareValue,
                    dmaWriteResp: DmaWriteResp {
                        sqpn: cntrl.getSQPN,
                        psn : endPSN
                    }
                };
                if (isNormalCase) begin
                    payloadConRespQ.enq(payloadConResp);
                end
            end

            let reqOpCode = case (pendingWR.wr.opcode)
                IBV_WR_SEND_WITH_IMM      : SEND_LAST_WITH_IMMEDIATE;
                IBV_WR_SEND_WITH_INV      : SEND_LAST_WITH_INVALIDATE;
                IBV_WR_RDMA_WRITE         : RDMA_WRITE_LAST;
                IBV_WR_RDMA_WRITE_WITH_IMM: RDMA_WRITE_LAST_WITH_IMMEDIATE;
                // IBV_WR_SEND
                default                   : SEND_LAST;
            endcase;

            let recvReqID = recvReqIdPipeOut.first;
            recvReqIdPipeOut.deq;

            maybeRecvReqID = tagged Valid recvReqID;
            let wcOpCode = isSendWorkReq(pendingWR.wr.opcode) ? IBV_WC_RECV : IBV_WC_RECV_RDMA_WITH_IMM;
            let wcFlags = hasImmDt ? IBV_WC_WITH_IMM : (hasIETH ? IBV_WC_WITH_INV : IBV_WC_NO_FLAGS);
            expectedWorkCompQ.enq(tuple5(recvReqID, wcOpCode, wcFlags, maybeImmDt, maybeRKey2Inv));

            let workCompReq = WorkCompGenReqRQ {
                rrID        : maybeRecvReqID,
                len         : pendingWR.wr.len,
                sqpn        : cntrl.getSQPN,
                reqPSN      : endPSN,
                isZeroDmaLen: isZeroLen,
                wcStatus    : isNormalCase ? IBV_WC_SUCCESS : IBV_WC_WR_FLUSH_ERR,
                reqOpCode   : reqOpCode,
                immDt       : maybeImmDt,
                rkey2Inv    : maybeRKey2Inv
            };

            workCompGenReqQ4RQ.enq(workCompReq);

            // $display("time=%0d: workCompReq=", $time, fshow(workCompReq));
        end
    endrule

    rule compare;
        let {
            recvReqID, wcOpCode, wcFlags, maybeImmDt, maybeRKey2Inv
        } = expectedWorkCompQ.first;
        expectedWorkCompQ.deq;

        let workCompRQ = dut.workCompPipeOut.first;
        dut.workCompPipeOut.deq;

        dynAssert(
            workCompRQ.id == recvReqID,
            "workCompRQ.id assertion @ mkTestWorkCompGenRQ",
            $format(
                "WC id=", fshow(workCompRQ.id),
                " not match expected WC recvReqID=", fshow(recvReqID))
        );

        dynAssert(
            workCompRQ.opcode == wcOpCode,
            "workCompRQ.opcode assertion @ mkTestWorkCompGenRQ",
            $format(
                "WC opcode=", fshow(workCompRQ.opcode),
                " not match expected WC opcode=", fshow(wcOpCode))
        );

        dynAssert(
            workCompRQ.flags == wcFlags,
            "workCompRQ.flags assertion @ mkTestWorkCompGenRQ",
            $format(
                "WC flags=", fshow(workCompRQ.flags),
                " not match expected WC flags=", fshow(wcFlags))
        );

        dynAssert(
            workCompRQ.immDt == maybeImmDt,
            "workCompRQ.immDt assertion @ mkTestWorkCompGenRQ",
            $format(
                "WC immDt=", fshow(workCompRQ.immDt),
                " not match expected WC immDt=", fshow(maybeImmDt))
        );

        dynAssert(
            workCompRQ.rkey2Inv == maybeRKey2Inv,
            "workCompRQ.rkey2Inv assertion @ mkTestWorkCompGenRQ",
            $format(
                "WC rkey2Inv=", fshow(workCompRQ.rkey2Inv),
                " not match expected WC rkey2Inv=", fshow(maybeRKey2Inv))
        );

        let expectedWorkCompStatus = isNormalCase ? IBV_WC_SUCCESS : IBV_WC_WR_FLUSH_ERR;
        dynAssert(
            workCompRQ.status == expectedWorkCompStatus,
            "workCompRQ.status assertion @ mkTestWorkCompGenRQ",
            $format(
                "WC status=", fshow(workCompRQ.status),
                " not match expected status=", fshow(expectedWorkCompStatus)
            )
        );

        countDown.decr;
        // $display("time=%0d: WC=", $time, fshow(workCompRQ));
    endrule
endmodule
