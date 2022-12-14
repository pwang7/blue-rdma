import Cntrs :: *;
import FIFOF :: *;
import PAClib :: *;
import Vector :: *;

import Assertions :: *;
import Controller :: *;
import DataTypes :: *;
import Headers :: *;
import MetaData :: *;
import Settings :: *;
import PrimUtils :: *;
import Utils :: *;
import Utils4Test :: *;

typedef enum {
    TEST_ST_FILL,
    TEST_ST_ACT,
    TEST_ST_POP
} SeqTestState deriving(Bits, Eq);

(* synthesize *)
module mkTestPDs(Empty);
    let pdDut <- mkPDs;
    Count#(Bit#(TLog#(MAX_PD))) pdCnt <- mkCount(0);

    PipeOut#(PdKey) pdKeyPipeOut <- mkGenericRandomPipeOut;
    Vector#(2, PipeOut#(PdKey)) pdKeyPipeOutVec <-
        mkForkVector(pdKeyPipeOut);
    let pdKeyPipeOut4InsertReq = pdKeyPipeOutVec[0];
    let pdKeyPipeOut4InsertResp <- mkBufferN(2, pdKeyPipeOutVec[1]);
    FIFOF#(PdHandler) pdHandlerQ4Search <- mkSizedFIFOF(valueOf(MAX_PD));
    FIFOF#(PdHandler) pdHandlerQ4Pop <- mkSizedFIFOF(valueOf(MAX_PD));

    Reg#(SeqTestState) pdTestStateReg <- mkReg(TEST_ST_FILL);

    let countDown <- mkCountDown(valueOf(MAX_CMP_CNT));

    rule allocPDs if (pdTestStateReg == TEST_ST_FILL);
        if (pdDut.notFull) begin
            let curPdKey = pdKeyPipeOut4InsertReq.first;
            pdKeyPipeOut4InsertReq.deq;

            pdDut.allocPD(curPdKey);
        end
    endrule

    rule allocResp if (pdTestStateReg == TEST_ST_FILL);
        if (isAllOnes(pdCnt)) begin
            pdCnt <= 0;
            pdTestStateReg <= TEST_ST_ACT;
        end
        else begin
            pdCnt.incr(1);
        end

        let pdHandler <- pdDut.allocResp;
        pdHandlerQ4Search.enq(pdHandler);
        pdHandlerQ4Pop.enq(pdHandler);

        let pdKey = pdKeyPipeOut4InsertResp.first;
        pdKeyPipeOut4InsertResp.deq;

        dynAssert(
            pdKey == truncate(pdHandler),
            "pdKey assertion @ mkTestPDs",
            $format(
                "pdKey=%h should match pdHandler=%h",
                pdKey, pdHandler
            )
        );
        // $display(
        //     "time=%0d: pdKey=%h, pdHandler=%h, pdCnt=%b when allocate PDs, pdDut.notFull=",
        //     $time, pdKey, pdHandler, pdCnt, fshow(pdDut.notFull)
        // );
    endrule

    rule compareSearch if (pdTestStateReg == TEST_ST_ACT);
        if (isAllOnes(pdCnt)) begin
            pdCnt <= 0;
            pdTestStateReg <= TEST_ST_POP;
        end
        else begin
            pdCnt.incr(1);
        end

        let pdHandler2Search = pdHandlerQ4Search.first;
        pdHandlerQ4Search.deq;

        let isValidPD = pdDut.isValidPD(pdHandler2Search);
        dynAssert(
            isValidPD,
            "isValidPD assertion @ mkTestPDs",
            $format(
                "isValidPD=", fshow(isValidPD),
                " should be valid when pdHandler2Search=%h and pdCnt=%0d",
                pdHandler2Search, pdCnt
            )
        );

        let maybeMRs = pdDut.getMRs(pdHandler2Search);
        dynAssert(
            isValid(maybeMRs),
            "maybeMRs assertion @ mkTestPDs",
            $format(
                "isValid(maybeMRs)=", fshow(isValid(maybeMRs)),
                " should be valid when pdHandler2Search=%h and pdCnt=%0d",
                pdHandler2Search, pdCnt
            )
        );
        // $display(
        //     "time=%0d: isValid(maybeMRs)=", $time, fshow(isValid(maybeMRs)),
        //     " should be valid when pdHandler2Search=%0d and pdCnt=%0d",
        //     pdHandler2Search, pdCnt
        // );
    endrule

    rule deAllocPDs if (pdTestStateReg == TEST_ST_POP);
        if (pdDut.notEmpty) begin
            let pdHandler2Remove = pdHandlerQ4Pop.first;
            pdHandlerQ4Pop.deq;

            pdDut.deAllocPD(pdHandler2Remove);
        end
    endrule

    rule deAllocResp if (pdTestStateReg == TEST_ST_POP);
        countDown.decr;

        if (isAllOnes(pdCnt)) begin
            pdCnt <= 0;
            pdTestStateReg <= TEST_ST_FILL;
        end
        else begin
            pdCnt.incr(1);
        end

        let removeResp <- pdDut.deAllocResp;

        dynAssert(
            removeResp,
            "removeResp assertion @ mkTestPDs",
            $format(
                "removeResp=", fshow(removeResp),
                " should be true when pdCnt=%0d",
                pdCnt
            )
        );
        // $display(
        //     "time=%0d: removeResp=", $time, fshow(removeResp),
        //     " should be true when pdCnt=%0d",
        //     pdCnt
        // );
    endrule
endmodule

(* synthesize *)
module mkTestMRs(Empty);
    let mrDut <- mkMRs;
    Count#(Bit#(TLog#(MAX_MR_PER_PD))) mrCnt <- mkCount(0);

    PipeOut#(MrKeyPart) mrKeyPipeOut <- mkGenericRandomPipeOut;
    Vector#(2, PipeOut#(MrKeyPart)) mrKeyPipeOutVec <-
        mkForkVector(mrKeyPipeOut);
    let mrKeyPipeOut4InsertReq = mrKeyPipeOutVec[0];
    let mrKeyPipeOut4InsertResp <- mkBufferN(2, mrKeyPipeOutVec[1]);
    FIFOF#(MrIndex) mrIndexQ4Search <- mkSizedFIFOF(valueOf(MAX_MR_PER_PD));
    FIFOF#(MrIndex) mrIndexQ4Pop <- mkSizedFIFOF(valueOf(MAX_MR_PER_PD));

    Reg#(SeqTestState) mrTestStateReg <- mkReg(TEST_ST_FILL);

    let countDown <- mkCountDown(valueOf(MAX_CMP_CNT));

    rule allocMRs if (mrTestStateReg == TEST_ST_FILL);
        if (mrDut.notFull) begin
            let curMrKey = mrKeyPipeOut4InsertReq.first;
            mrKeyPipeOut4InsertReq.deq;

            mrDut.allocMR(
                dontCareValue,        // laddr
                dontCareValue,        // len
                dontCareValue,        // accType
                dontCareValue,        // pdHandler
                curMrKey,             // lkeyPart
                tagged Valid curMrKey // rkeyPart
            );
        end
    endrule

    rule allocResp if (mrTestStateReg == TEST_ST_FILL);
        if (isAllOnes(mrCnt)) begin
            mrCnt <= 0;
            mrTestStateReg <= TEST_ST_ACT;
        end
        else begin
            mrCnt.incr(1);
        end

        let { mrIndex, lkey, rkey } <- mrDut.allocResp;
        mrIndexQ4Search.enq(mrIndex);
        mrIndexQ4Pop.enq(mrIndex);

        let mrKeyPart = mrKeyPipeOut4InsertResp.first;
        mrKeyPipeOut4InsertResp.deq;

        dynAssert(
            mrKeyPart == truncate(lkey),
            "lkey assertion @ mkTestMRs",
            $format(
                "lkey=%h should match mrKeyPart=%h",
                lkey, mrKeyPart
            )
        );
        let rkeyValue = unwrapMaybe(rkey);
        dynAssert(
            isValid(rkey) && mrKeyPart == truncate(rkeyValue),
            "rkey assertion @ mkTestMRs",
            $format(
                "rkey=%h should match mrKeyPart=%h",
                rkeyValue, mrKeyPart
            )
        );

        // $display(
        //     "time=%0d: mrIndex=%h, lkey=%h, rkey=%h, mrCnt=%b when allocate MRs, mrDut.notFull=",
        //     $time, mrIndex, lkey, rkey, mrCnt, fshow(mrDut.notFull)
        // );
    endrule

    rule compareSearch if (mrTestStateReg == TEST_ST_ACT);
        if (isAllOnes(mrCnt)) begin
            mrCnt <= 0;
            mrTestStateReg <= TEST_ST_POP;
        end
        else begin
            mrCnt.incr(1);
        end

        let mrIndex2Search = mrIndexQ4Search.first;
        mrIndexQ4Search.deq;

        let maybeMR = mrDut.getMR(mrIndex2Search);
        dynAssert(
            isValid(maybeMR),
            "maybeMR assertion @ mkTestMRs",
            $format(
                "maybeMR=", fshow(maybeMR),
                " should be valid when mrIndex2Search=%h and mrCnt=%0d",
                mrIndex2Search, mrCnt
            )
        );
        // $display(
        //     "time=%0d: maybeMR=", $time, fshow(maybeMR),
        //     " should be valid when mrIndex2Search=%0d and mrCnt=%0d",
        //     mrIndex2Search, mrCnt
        // );
    endrule

    rule deAllocMRs if (mrTestStateReg == TEST_ST_POP);
        if (mrDut.notEmpty) begin
            let mrIndex2Remove = mrIndexQ4Pop.first;
            mrIndexQ4Pop.deq;

            mrDut.deAllocMR(mrIndex2Remove);
        end
    endrule

    rule deAllocResp if (mrTestStateReg == TEST_ST_POP);
        countDown.decr;

        if (isAllOnes(mrCnt)) begin
            mrCnt <= 0;
            mrTestStateReg <= TEST_ST_FILL;
        end
        else begin
            mrCnt.incr(1);
        end

        let removeResp <- mrDut.deAllocResp;

        dynAssert(
            removeResp,
            "removeResp assertion @ mkTestMRs",
            $format(
                "removeResp=", fshow(removeResp),
                " should be true when mrCnt=%0d",
                mrCnt
            )
        );
        // $display(
        //     "time=%0d: removeResp=", $time, fshow(removeResp),
        //     " should be true when mrCnt=%0d",
        //     mrCnt
        // );
    endrule
endmodule

(* synthesize *)
module mkTestQPs(Empty);
    let qpDut <- mkQPs;
    Count#(Bit#(TLog#(MAX_QP))) qpCnt <- mkCount(0);

    PipeOut#(PdHandler) pdHandlerPipeOut <- mkGenericRandomPipeOut;
    Vector#(3, PipeOut#(PdHandler)) pdHandlerPipeOutVec <-
        mkForkVector(pdHandlerPipeOut);
    let pdHandlerPipeOut4InsertReq = pdHandlerPipeOutVec[0];
    let pdHandlerPipeOut4InsertResp <- mkBufferN(2, pdHandlerPipeOutVec[1]);
    let pdHandlerPipeOut4Search <- mkBufferN(valueOf(MAX_QP), pdHandlerPipeOutVec[2]);
    FIFOF#(QPN) qpnQ4Search <- mkSizedFIFOF(valueOf(MAX_QP));
    FIFOF#(QPN) qpnQ4Pop <- mkSizedFIFOF(valueOf(MAX_QP));

    Reg#(SeqTestState) qpTestStateReg <- mkReg(TEST_ST_FILL);

    let countDown <- mkCountDown(valueOf(MAX_CMP_CNT));

    rule createQPs if (qpTestStateReg == TEST_ST_FILL);
        if (qpDut.notFull) begin
            let curPdHandler = pdHandlerPipeOut4InsertReq.first;
            pdHandlerPipeOut4InsertReq.deq;

            qpDut.createQP(curPdHandler);
        end
    endrule

    rule createResp if (qpTestStateReg == TEST_ST_FILL);
        if (isAllOnes(qpCnt)) begin
            qpCnt <= 0;
            qpTestStateReg <= TEST_ST_ACT;
        end
        else begin
            qpCnt.incr(1);
        end

        let qpn <- qpDut.createResp;
        qpnQ4Search.enq(qpn);
        qpnQ4Pop.enq(qpn);

        let refPdHandler = pdHandlerPipeOut4InsertResp.first;
        pdHandlerPipeOut4InsertResp.deq;

        Bit#(TSub#(QPN_WIDTH, QP_INDEX_WIDTH)) refPart = truncateLSB(refPdHandler);
        Bit#(TSub#(QPN_WIDTH, QP_INDEX_WIDTH)) qpnPart = truncate(qpn);
        dynAssert(
            qpnPart == refPart,
            "qpnPart assertion @ mkTestQPs",
            $format(
                "qpnPart=%h should match refPart=%h",
                qpnPart, refPart
            )
        );

        // $display(
        //     "time=%0d: qpn=%h should match refPdHandler=%h",
        //     $time, qpn, refPdHandler
        // );
    endrule

    rule compareSearch if (qpTestStateReg == TEST_ST_ACT);
        if (isAllOnes(qpCnt)) begin
            qpCnt <= 0;
            qpTestStateReg <= TEST_ST_POP;
        end
        else begin
            qpCnt.incr(1);
        end

        let qpn2Search = qpnQ4Search.first;
        qpnQ4Search.deq;

        let isValidQP = qpDut.isValidQP(qpn2Search);
        dynAssert(
            isValidQP,
            "isValidQP assertion @ mkTestQPs",
            $format(
                "isValidQP=", fshow(isValidQP),
                " should be valid when qpn2Search=%h and qpCnt=%0d",
                qpn2Search, qpCnt
            )
        );

        let maybePD = qpDut.getPD(qpn2Search);
        dynAssert(
            isValid(maybePD),
            "maybePD assertion @ mkTestQPs",
            $format(
                "maybePD=", fshow(isValid(maybePD)),
                " should be valid"
            )
        );

        let pdHandler = unwrapMaybe(maybePD);
        let refPdHandler = pdHandlerPipeOut4Search.first;
        pdHandlerPipeOut4Search.deq;

        dynAssert(
            pdHandler == refPdHandler,
            "pdHandler assertion @ mkTestQPs",
            $format(
                "pdHandler=%h should match refPdHandler=%h",
                pdHandler, refPdHandler
            )
        );

        let qpCntrl = qpDut.getCntrl(qpn2Search);
        dynAssert(
            qpCntrl.isReset,
            "qpCntrl assertion @ mkTestQPs",
            $format(
                "qpCntrl.isReset=", fshow(qpCntrl.isReset),
                " should be true"
            )
        );
        // let maybeQpCntrl = qpDut.getCntrl2(qpn2Search);
        // dynAssert(
        //     isValid(maybeQpCntrl),
        //     "isValid(maybeQpCntrl) assertion @ mkTestQPs",
        //     $format(
        //         "isValid(maybeQpCntrl)=", fshow(isValid(maybeQpCntrl)),
        //         " should be true"
        //     )
        // );

        // $display(
        //     "time=%0d: isValidQP=", $time, fshow(isValidQP),
        //     " should be valid when qpn2Search=%h and qpCnt=%0d",
        //     qpn2Search, qpCnt
        // );
    endrule

    rule destroyQPs if (qpTestStateReg == TEST_ST_POP);
        if (qpDut.notEmpty) begin
            let qpn2Remove = qpnQ4Pop.first;
            qpnQ4Pop.deq;

            qpDut.destroyQP(qpn2Remove);
        end
    endrule

    rule destroyResp if (qpTestStateReg == TEST_ST_POP);
        countDown.decr;

        if (isAllOnes(qpCnt)) begin
            qpCnt <= 0;
            qpTestStateReg <= TEST_ST_FILL;
        end
        else begin
            qpCnt.incr(1);
        end

        let removeResp <- qpDut.destroyResp;

        dynAssert(
            removeResp,
            "removeResp assertion @ mkTestQPs",
            $format(
                "removeResp=", fshow(removeResp),
                " should be true when qpCnt=%0d",
                qpCnt
            )
        );
        // $display(
        //     "time=%0d: removeResp=", $time, fshow(removeResp),
        //     " should be true when qpCnt=%0d",
        //     qpCnt
        // );
    endrule
endmodule

(* synthesize *)
module mkTestPermCheckMR(Empty);
    let pdMetaData  <- mkPDs;
    let permCheckMR <- mkPermCheckMR(pdMetaData);

    Count#(Bit#(TLog#(TAdd#(1, MAX_PD))))         pdCnt <- mkCount(0);
    Count#(Bit#(TLog#(TAdd#(1, MAX_MR_PER_PD))))  mrCnt <- mkCount(0);
    Count#(Bit#(TLog#(TAdd#(1, MAX_PD)))) mrMetaDataCnt <- mkCount(0);
    Count#(Bit#(TLog#(TMul#(2, TMul#(MAX_PD, MAX_MR_PER_PD))))) searchCnt <- mkCount(0);

    PipeOut#(PdKey) pdKeyPipeOut <- mkGenericRandomPipeOut;
    PipeOut#(MrKeyPart) mrKeyPipeOut <- mkGenericRandomPipeOut;

    FIFOF#(PdHandler) pdHandlerQ4FillMR <- mkFIFOF;
    FIFOF#(Tuple2#(PdHandler, LKEY)) lKeyQ4Search <- mkSizedFIFOF(valueOf(TMul#(MAX_PD, MAX_MR_PER_PD)));
    FIFOF#(Tuple2#(PdHandler, RKEY)) rKeyQ4Search <- mkSizedFIFOF(valueOf(TMul#(MAX_PD, MAX_MR_PER_PD)));
    FIFOF#(PermCheckInfo) lKeyPermCheckInfoQ <- mkFIFOF;
    FIFOF#(PermCheckInfo) rKeyPermCheckInfoQ <- mkFIFOF;

    Reg#(SeqTestState) mrCheckStateReg <- mkReg(TEST_ST_FILL);

    let countDown <- mkCountDown(valueOf(MAX_CMP_CNT));

    ADDR defaultAddr = fromInteger(0);
    Length defaultLen = fromInteger(valueOf(RDMA_MAX_LEN));
    let defaultAccPerm = IBV_ACCESS_REMOTE_WRITE;

    rule allocPDs if (pdCnt < fromInteger(valueOf(MAX_PD)) && mrCheckStateReg == TEST_ST_FILL);
        pdCnt.incr(1);
        let curPdKey = pdKeyPipeOut.first;
        pdKeyPipeOut.deq;

        pdMetaData.allocPD(curPdKey);

        // $display("time=%0d: curPdKey=%h", $time, curPdKey);
    endrule

    rule allocRespPDs if (mrCheckStateReg == TEST_ST_FILL);
        let pdHandler <- pdMetaData.allocResp;
        pdHandlerQ4FillMR.enq(pdHandler);

        // $display("time=%0d: pdHandler=%h", $time, pdHandler);
    endrule

    rule allocMRs if (mrCheckStateReg == TEST_ST_FILL);
        let pdHandler = pdHandlerQ4FillMR.first;
        let maybeMRs = pdMetaData.getMRs(pdHandler);
        dynAssert(
            isValid(maybeMRs),
            "maybeMRs assertion @ mkTestPermCheckMR",
            $format(
                "isValid(maybeMRs)=", fshow(isValid(maybeMRs)),
                " should be valid for pdHandler=%h", pdHandler
            )
        );

        // let mrMetaData = unwrapMaybe(maybeMRs);
        if (maybeMRs matches tagged Valid .mrMetaData &&& mrMetaData.notFull) begin
            let curMrKey = mrKeyPipeOut.first;
            mrKeyPipeOut.deq;

            mrMetaData.allocMR(
                defaultAddr,          // laddr
                defaultLen,           // len
                defaultAccPerm,       // accType
                pdHandler,            // pdHandler
                curMrKey,             // lkeyPart
                tagged Valid curMrKey // rkeyPart
            );

            // $display("time=%0d: curMrKey=%h", $time, curMrKey);
        end
    endrule

    rule allocRespMRs if (mrCheckStateReg == TEST_ST_FILL);
        if (mrMetaDataCnt < fromInteger(valueOf(MAX_PD))) begin
            if (mrCnt < fromInteger(valueOf(MAX_MR_PER_PD))) begin
                mrCnt.incr(1);

                let pdHandler = pdHandlerQ4FillMR.first;
                let maybeMRs = pdMetaData.getMRs(pdHandler);
                dynAssert(
                    isValid(maybeMRs),
                    "maybeMRs assertion @ mkTestPermCheckMR",
                    $format(
                        "isValid(maybeMRs)=", fshow(isValid(maybeMRs)),
                        " should be valid for pdHandler=%h", pdHandler
                    )
                );

                if (maybeMRs matches tagged Valid .mrMetaData) begin
                    let { mrIndex, lkey, rkey } <- mrMetaData.allocResp;

                    dynAssert(
                        isValid(rkey),
                        "rkey assertion @ mkTestPermCheckMR",
                        $format("rkey=", rkey, " should be valid")
                    );

                    lKeyQ4Search.enq(tuple2(pdHandler, lkey));
                    rKeyQ4Search.enq(tuple2(pdHandler, unwrapMaybe(rkey)));

                    // $display("time=%0d: mrIndex=%h", $time, mrIndex);
                end
            end
            else begin
                mrCnt <= 0;
                mrMetaDataCnt.incr(1);
                pdHandlerQ4FillMR.deq;
            end
        end
        else begin
            mrMetaDataCnt <= 0;
            searchCnt <= fromInteger(valueOf(TSub#(TMul#(2, TMul#(MAX_PD, MAX_MR_PER_PD)), 1)));
            mrCheckStateReg <= TEST_ST_ACT;
        end

        // $display(
        //     "time=%0d: mrMetaDataCnt=%h, mrCnt=%h", $time, mrMetaDataCnt, mrCnt
        // );
    endrule

    rule checkReqByLKey if (lKeyQ4Search.notEmpty && mrCheckStateReg == TEST_ST_ACT);
        let { pdHandler, lkey } = lKeyQ4Search.first;
        lKeyQ4Search.deq;

        let permCheckInfo = PermCheckInfo {
            wrID         : tagged Invalid,
            lkey         : lkey,
            rkey         : dontCareValue,
            localOrRmtKey: True,
            laddr        : defaultAddr,
            totalLen     : defaultLen,
            pdHandler    : pdHandler,
            isZeroDmaLen : isZero(defaultLen),
            accType      : defaultAccPerm
        };

        permCheckMR.checkReq(permCheckInfo);
        // lKeyPermCheckInfoQ.enq(permCheckInfo);

        // $display(
        //     "time=%0d: permCheckInfo=", $time, fshow(permCheckInfo)
        // );
    endrule

    rule checkReqByRKey if (!lKeyQ4Search.notEmpty && mrCheckStateReg == TEST_ST_ACT);
        let { pdHandler, rkey } = rKeyQ4Search.first;
        rKeyQ4Search.deq;

        let permCheckInfo = PermCheckInfo {
            wrID         : tagged Invalid,
            lkey         : dontCareValue,
            rkey         : rkey,
            localOrRmtKey: False,
            laddr        : defaultAddr,
            totalLen     : defaultLen,
            pdHandler    : pdHandler,
            isZeroDmaLen : isZero(defaultLen),
            accType      : defaultAccPerm
        };

        permCheckMR.checkReq(permCheckInfo);
        // rKeyPermCheckInfoQ.enq(permCheckInfo);
    endrule

    rule checkResp if (mrCheckStateReg == TEST_ST_ACT);
        countDown.decr;

        // if (lKeyPermCheckInfoQ.notEmpty) begin
        //     let lKeyCheckResp <- permCheckMR.checkResp;
        //     dynAssert(
        //         lKeyCheckResp,
        //         "lKeyCheckResp @ mkTestPermCheckMR",
        //         $format(
        //             "lKeyCheckResp=", fshow(lKeyCheckResp),
        //             " should be true"
        //         )
        //     );
        //     searchCnt.decr(1);

        //     $display(
        //         "time=%0d: lKeyCheckResp=", $time, fshow(lKeyCheckResp), " should be true"
        //     );
        // end
        // else if (rKeyPermCheckInfoQ.notEmpty) begin
        //     let rKeyCheckResp <- permCheckMR.checkResp;
        //     dynAssert(
        //         rKeyCheckResp,
        //         "rKeyCheckResp @ mkTestPermCheckMR",
        //         $format(
        //             "rKeyCheckResp=", fshow(rKeyCheckResp),
        //             " should be true"
        //         )
        //     );
        //     searchCnt.decr(1);

        //     $display(
        //         "time=%0d: rKeyCheckResp=", $time, fshow(rKeyCheckResp), " should be true"
        //     );
        // end

        let checkResp <- permCheckMR.checkResp;
        dynAssert(
            checkResp,
            "checkResp @ mkTestPermCheckMR",
            $format(
                "checkResp=", fshow(checkResp), " should be true"
            )
        );

        if (searchCnt == 0) begin
            mrCheckStateReg <= TEST_ST_POP;
        end
        else begin
            searchCnt.decr(1);
        end

        // $display(
        //     "time=%0d: searchCnt=%0d, checkResp=",
        //     $time, searchCnt, fshow(checkResp),
        //     " should be true"
        // );
    endrule

    rule clear if (mrCheckStateReg == TEST_ST_POP);
        pdCnt <= 0;
        mrCnt <= 0;
        mrMetaDataCnt <= 0;

        pdHandlerQ4FillMR.clear;
        lKeyQ4Search.clear;
        rKeyQ4Search.clear;
        // lKeyPermCheckInfoQ.clear;
        // rKeyPermCheckInfoQ.clear;

        pdMetaData.clear;

        mrCheckStateReg <= TEST_ST_FILL;

        // $display("time=%0d: clear", $time);
    endrule
endmodule
