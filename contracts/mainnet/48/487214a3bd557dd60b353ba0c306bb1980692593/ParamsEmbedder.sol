// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Ownable.sol";
import "./Strings.sol";
import "./ICode.sol";

contract ParamsEmbedder is ICode, Ownable{

    function getCode(string calldata params) external pure override returns(string memory) {
        return string.concat(
            'function parseUrlParams() { return ',
                params,
            '}'
        );
    }
}

