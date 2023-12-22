
// SPDX-License-Identifier: AML
//
// Copyright 2017 Christian Reitwiessner
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.

// 2019 OKIMS

pragma solidity ^0.8.0;

library PairingCommittee {

    uint256 constant PRIME_Q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    struct G1Point {
        uint256 X;
        uint256 Y;
    }

    // Encoding of field elements is: X[0] * z + X[1]
    struct G2Point {
        uint256[2] X;
        uint256[2] Y;
    }

    /*
     * @return The negation of p, i.e. p.plus(p.negate()) should be zero.
     */
    function negate(G1Point memory p) internal pure returns (G1Point memory) {

        // The prime q in the base field F_q for G1
        if (p.X == 0 && p.Y == 0) {
            return G1Point(0, 0);
        } else {
            return G1Point(p.X, PRIME_Q - (p.Y % PRIME_Q));
        }
    }

    /*
     * @return The sum of two points of G1
     */
    function plus(
        G1Point memory p1,
        G1Point memory p2
    ) internal view returns (G1Point memory r) {

        uint256[4] memory input;
        input[0] = p1.X;
        input[1] = p1.Y;
        input[2] = p2.X;
        input[3] = p2.Y;
        bool success;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 6, input, 0xc0, r, 0x60)
        // Use "invalid" to make gas estimation work
            switch success case 0 { invalid() }
        }

        require(success,"PairingCommittee-add-failed");
    }

    /*
     * @return The product of a point on G1 and a scalar, i.e.
     *         p == p.scalar_mul(1) and p.plus(p) == p.scalar_mul(2) for all
     *         points p.
     */
    function scalar_mul(G1Point memory p, uint256 s) internal view returns (G1Point memory r) {

        uint256[3] memory input;
        input[0] = p.X;
        input[1] = p.Y;
        input[2] = s;
        bool success;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 7, input, 0x80, r, 0x60)
        // Use "invalid" to make gas estimation work
            switch success case 0 { invalid() }
        }
        require (success,"PairingCommittee-mul-failed");
    }

    /* @return The result of computing the PairingCommittee check
     *         e(p1[0], p2[0]) *  .... * e(p1[n], p2[n]) == 1
     *         For example,
     *         PairingCommittee([P1(), P1().negate()], [P2(), P2()]) should return true.
     */
    function pairing(
        G1Point memory a1,
        G2Point memory a2,
        G1Point memory b1,
        G2Point memory b2,
        G1Point memory c1,
        G2Point memory c2,
        G1Point memory d1,
        G2Point memory d2
    ) internal view returns (bool) {

        G1Point[4] memory p1 = [a1, b1, c1, d1];
        G2Point[4] memory p2 = [a2, b2, c2, d2];
        uint256 inputSize = 24;
        uint256[] memory input = new uint256[](inputSize);

        for (uint256 i = 0; i < 4; i++) {
            uint256 j = i * 6;
            input[j + 0] = p1[i].X;
            input[j + 1] = p1[i].Y;
            input[j + 2] = p2[i].X[0];
            input[j + 3] = p2[i].X[1];
            input[j + 4] = p2[i].Y[0];
            input[j + 5] = p2[i].Y[1];
        }

        uint256[1] memory out;
        bool success;

        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 8, add(input, 0x20), mul(inputSize, 0x20), out, 0x20)
        // Use "invalid" to make gas estimation work
            switch success case 0 { invalid() }
        }

        require(success,"PairingCommittee-opcode-failed");

        return out[0] != 0;
    }
}

contract EthSyncCommitteeVerifier {

    using PairingCommittee for *;

    uint256 constant SNARK_SCALAR_FIELD_COMMITTEE = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint256 constant PRIME_Q_COMMITTEE = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    struct VerifyingKeyCommittee {
        PairingCommittee.G1Point alfa1;
        PairingCommittee.G2Point beta2;
        PairingCommittee.G2Point gamma2;
        PairingCommittee.G2Point delta2;
        PairingCommittee.G1Point[2] IC;
    }

    struct ProofCommittee {
        PairingCommittee.G1Point A;
        PairingCommittee.G2Point B;
        PairingCommittee.G1Point C;
    }

    function verifyingKeyCommittee() internal pure returns (VerifyingKeyCommittee memory vk) {
        vk.alfa1 = PairingCommittee.G1Point(uint256(14957596721231844749478690877664170287507304031660753196481061521657484686386), uint256(486325762719989718819674915079468245664179087648099920569752352327990294254));
        vk.beta2 = PairingCommittee.G2Point([uint256(19413442024568246248078977547382115227244527546752320736703994543356580698023), uint256(7383700747549901376257000451032619235229896279187794580576663680824556529418)], [uint256(16479916357302892675705297549399875501476343835799432397924132775800054737649), uint256(8166160905070027909912268880814292704277694170979531562591890568065589628394)]);
        vk.gamma2 = PairingCommittee.G2Point([uint256(452921715714006248554747553051530202389686253612917289449689892959275978129), uint256(19079972952167792101680113587488302899375835867925262583415721261254727524264)], [uint256(15353497313609112770132737297797025951416074676346516434265458904676598455556), uint256(15998361846571001995156207227548423729139520781825863894716123038568963832545)]);
        vk.delta2 = PairingCommittee.G2Point([uint256(18815280668067448032005569628605436972083622512681018993721033576941755890521), uint256(21874146397664684252874383724255032316920106371336935550505633607878366567494)], [uint256(9333459811005625355087002349451580652250421196200958504793725528824167787917), uint256(3021250037278445602933107173728561710688823914950492301409463944599559777116)]);
        vk.IC[0] = PairingCommittee.G1Point(uint256(1828793311211900021577864646535069549530919251007884590451221826689575833534), uint256(16452253905301369944653152445860336893844423712435591198462755624529310585907));
        vk.IC[1] = PairingCommittee.G1Point(uint256(14931435484589449896056227725837653830131569674661763250246418499419699915256), uint256(17444263099949786346372107772762500984076947959244868122723776691119279463959));
    }

    /*
     * @returns Whether the proof is valid given the hardcoded verifying key
     *          above and the public inputs
     */
    function verifyCommitteeProof(
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[1] memory input
    ) public view returns (bool r) {

        ProofCommittee memory proof;
        proof.A = PairingCommittee.G1Point(a[0], a[1]);
        proof.B = PairingCommittee.G2Point([b[0][0], b[0][1]], [b[1][0], b[1][1]]);
        proof.C = PairingCommittee.G1Point(c[0], c[1]);

        VerifyingKeyCommittee memory vk = verifyingKeyCommittee();

        // Compute the linear combination vk_x
        PairingCommittee.G1Point memory vk_x = PairingCommittee.G1Point(0, 0);

        // Make sure that proof.A, B, and C are each less than the prime q
        require(proof.A.X < PRIME_Q_COMMITTEE, "verifier-aX-gte-prime-q");
        require(proof.A.Y < PRIME_Q_COMMITTEE, "verifier-aY-gte-prime-q");

        require(proof.B.X[0] < PRIME_Q_COMMITTEE, "verifier-bX0-gte-prime-q");
        require(proof.B.Y[0] < PRIME_Q_COMMITTEE, "verifier-bY0-gte-prime-q");

        require(proof.B.X[1] < PRIME_Q_COMMITTEE, "verifier-bX1-gte-prime-q");
        require(proof.B.Y[1] < PRIME_Q_COMMITTEE, "verifier-bY1-gte-prime-q");

        require(proof.C.X < PRIME_Q_COMMITTEE, "verifier-cX-gte-prime-q");
        require(proof.C.Y < PRIME_Q_COMMITTEE, "verifier-cY-gte-prime-q");

        // Make sure that every input is less than the snark scalar field
        for (uint256 i = 0; i < input.length; i++) {
            require(input[i] < SNARK_SCALAR_FIELD_COMMITTEE,"verifier-gte-snark-scalar-field");
            vk_x = PairingCommittee.plus(vk_x, PairingCommittee.scalar_mul(vk.IC[i + 1], input[i]));
        }

        vk_x = PairingCommittee.plus(vk_x, vk.IC[0]);

        return PairingCommittee.pairing(
            PairingCommittee.negate(proof.A),
            proof.B,
            vk.alfa1,
            vk.beta2,
            vk_x,
            vk.gamma2,
            proof.C,
            vk.delta2
        );
    }
}

