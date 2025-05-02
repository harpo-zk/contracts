// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

struct HarpoPrivateData {
    bytes32 cipher;
    bytes32[2] c1;
}

struct HarpoPrivateDataProof2pk {
    uint[2] a;
    uint[2][2] b;
    uint[2] c;
    uint[2] input;
}

struct HarpoPrivateDataProof3pk {
    uint[2] a;
    uint[2][2] b;
    uint[2] c;
    uint[3] input;
}

struct HarpoPrivateParameter2pk {
    HarpoPrivateData[2] data;
    HarpoPrivateDataProof2pk proof;
}

struct HarpoPrivateParameter3pk {
    HarpoPrivateData[3] data;
    HarpoPrivateDataProof3pk proof;
}

interface HarpoPrivateDataVerifier2pk {
    function verifyProof(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[2] memory input
    ) external view returns (bool r);
}

interface HarpoPrivateDataVerifier3pk {
    function verifyProof(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[3] memory input
    ) external view returns (bool r);
}

contract HarpoPrivateDataRouter {

    HarpoPrivateDataVerifier2pk public harpoPrivateDataVerifier2pk;
    HarpoPrivateDataVerifier3pk public harpoPrivateDataVerifier3pk;

    constructor(address harpoPrivateDataVerifier2pkAddress, address harpoPrivateDataVerifier3pkAddress) {
        harpoPrivateDataVerifier2pk = HarpoPrivateDataVerifier2pk(harpoPrivateDataVerifier2pkAddress);
        harpoPrivateDataVerifier3pk = HarpoPrivateDataVerifier3pk(harpoPrivateDataVerifier3pkAddress);
    }

    function verifyProof(HarpoPrivateParameter2pk calldata data) public view {
        require(data.data[0].cipher == bytes32(data.proof.input[0]), "invalid harpo proof");
        require(data.data[1].cipher == bytes32(data.proof.input[1]), "invalid harpo proof");

        bool v = harpoPrivateDataVerifier2pk.verifyProof(data.proof.a, data.proof.b, data.proof.c, data.proof.input);
        if(!v) {
            revert("invalid harpo proof");
        }
    }

    function verifyProof(HarpoPrivateParameter3pk calldata data) public view {
        require(data.data[0].cipher == bytes32(data.proof.input[0]), "invalid harpo proof");
        require(data.data[1].cipher == bytes32(data.proof.input[1]), "invalid harpo proof");
        require(data.data[2].cipher == bytes32(data.proof.input[2]), "invalid harpo proof");

        bool v = harpoPrivateDataVerifier3pk.verifyProof(data.proof.a, data.proof.b, data.proof.c, data.proof.input);
        if(!v) {
            revert("invalid harpo proof");
        }
    }
}
