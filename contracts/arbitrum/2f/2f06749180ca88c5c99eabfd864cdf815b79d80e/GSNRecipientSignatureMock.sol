// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./GSNRecipient.sol";
import "./GSNRecipientSignature.sol";

contract GSNRecipientSignatureMock is GSNRecipient, GSNRecipientSignature {
    constructor(address trustedSigner) public GSNRecipientSignature(trustedSigner) { }

    event MockFunctionCalled();

    function mockFunction() public {
        emit MockFunctionCalled();
    }
}

