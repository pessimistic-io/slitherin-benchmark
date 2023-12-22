// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import { ERC20 } from "./ERC20.sol";
import { MintableERC20 } from "./MintableERC20.sol";
import { RadpieReceiptToken } from "./RadpieReceiptToken.sol";

library ERC20FactoryLib {
    function createERC20(string memory name_, string memory symbol_) public returns(address) 
    {
        ERC20 token = new MintableERC20(name_, symbol_);
        return address(token);
    }

    function createReceipt(address _stakeToken, address _masterPenpie, string memory _name, string memory _symbol) public returns(address)
    {
        ERC20 token = new RadpieReceiptToken(_stakeToken, _masterPenpie, _name, _symbol);
        return address(token);
    }
}
