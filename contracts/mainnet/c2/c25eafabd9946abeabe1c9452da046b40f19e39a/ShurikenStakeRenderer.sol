// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./Base64.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./ISVGData.sol";
import "./ICardSVGParts.sol";

contract ShurikenStakeRenderer is Ownable {
    using Strings for uint256;

    struct Datas {
        ISVGData bg1;
        ISVGData bg2;
        ISVGData bg3;
    }

    Datas public data;

    constructor(Datas memory _data) {
        data = _data;
    }

    function get() public view returns (bytes memory) {
        ISVGData target1 = data.bg1;
        ISVGData target2 = data.bg2;
        ISVGData target3 = data.bg3;
        return abi.encodePacked('data:image/svg+xml;base64,', target1.data(), target2.data(), target3.data());
    }

    function setDatas(Datas memory _data) public onlyOwner {
        data = _data;
    }
}

