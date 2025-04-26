// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.16;

struct HarpoPrivateData {
    bytes32 cipher;
    bytes32[2] c1;
}
struct HarpoPrivateDataProof {
    uint[2] a;
    uint[2][2] b;
    uint[2] c;
    uint[2] input;
}
struct HarpoPrivateParameter {
    HarpoPrivateData[2] data;
    HarpoPrivateDataProof proof;
}

interface HarpoPrivateDataVerifier {
    function verifyProof(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[2] memory input
    ) external view returns (bool r);
}

contract HarpoPrivateDataRouter {

    HarpoPrivateDataVerifier public harpoPrivateDataVerifier;

    constructor(address harpoPrivateDataVerifierAddress) {
        harpoPrivateDataVerifier = HarpoPrivateDataVerifier(harpoPrivateDataVerifierAddress);
    }

    function verifyProof(HarpoPrivateParameter calldata data) public view {
        require(data.data[0].cipher == bytes32(data.proof.input[0]), "invalid harpo proof");
        require(data.data[1].cipher == bytes32(data.proof.input[1]), "invalid harpo proof");

        bool v = harpoPrivateDataVerifier.verifyProof(data.proof.a, data.proof.b, data.proof.c, data.proof.input);
        if(!v) {
            revert("invalid harpo proof");
        }
    }
}
