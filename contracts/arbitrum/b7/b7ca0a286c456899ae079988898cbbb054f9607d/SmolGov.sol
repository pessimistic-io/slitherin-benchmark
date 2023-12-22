// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./ERC20.sol";

import "./SmolBrain.sol";

contract SmolGov is ERC20 {
    SmolBrain public smolbrain;

    constructor(address _smolbrain) ERC20("Smol Governance", "gSMOL") {
        smolbrain = SmolBrain(_smolbrain);
    }

    function totalSupply() public view override returns (uint256) {
        return smolbrain.totalSupply();
    }

    function balanceOf(address _account) public view override returns (uint256 balanceAtSchool) {
        uint256 balance = smolbrain.balanceOf(_account);
        School school = smolbrain.school();
        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = smolbrain.tokenOfOwnerByIndex(_account, i);
            if (school.isAtSchool(tokenId)) {
                balanceAtSchool++;
            }
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        revert("Non-transferable");
    }
}

