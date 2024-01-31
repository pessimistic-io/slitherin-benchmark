// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Ownable.sol";
import "./base64.sol";
import "./ICode.sol";

contract WebCode is ICode, Ownable{

    string public code_start =
        '<!DOCTYPE html>'
        '<html lang="en">'
        '<head><title>Pings by BlockMachine</title>'
        '<meta http-equiv="Content-Security-Policy" content="default-src \'self\';'
        'script-src \'self\' \'unsafe-inline\';'
        'style-src \'unsafe-inline\'">'
        '<meta charset="utf-8"/>'
        '<style>'
        'html, body{'
        'margin:0;'
        'padding:0;'
        '}'
        'canvas{'
        'display:block;'
        'height:100vh;'
        'width:100vw;'
        '}'
        '</style>'
        '</head>'
        '<body>'
        ''
;

    string public code_end =
        '</body>'
        '</html>';

    mapping (uint => ICode) public subCode;
    uint[] public codeOrder;

    function getCodeEncoded(string calldata params) external view returns(string memory) {
        return string.concat('data:text/html;base64,', Base64.encode(abi.encodePacked(getCode(params))));
    }

    function getCode(string calldata params) public view override returns(string memory) {
        string memory s = code_start;

        for (uint8 i = 0; i < codeOrder.length; i++) {
            uint idx = codeOrder[i];
            s = string.concat(s, "<script>", ICode(subCode[idx]).getCode(params), "</script>");
        }

        return string.concat(s, code_end);

    }

    function setOrder(uint[] calldata order) external virtual onlyOwner {
        codeOrder = order;
    }

    function addSubCode(address[] calldata addrs) external virtual onlyOwner {
        uint startIdx = codeOrder.length;
        for (uint i = startIdx; i < addrs.length + startIdx ; i++) {
            setSubCode(i, i, addrs[i]);
        }
    }

    function setSubCode(uint id, uint idx, address addr) public virtual onlyOwner {
        subCode[id] = ICode(addr);
        if(idx < codeOrder.length) {
            codeOrder[idx]=id;
        }
        else {
            codeOrder.push(id);
        }
    }

    function setCodeStart(string calldata code) public virtual onlyOwner {
        code_start = code;
    }

    function setCodeEnd(string calldata code) public virtual onlyOwner {
        code_end = code;
    }

}

