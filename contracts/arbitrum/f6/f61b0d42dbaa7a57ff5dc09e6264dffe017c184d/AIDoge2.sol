// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./IERC20.sol";

contract AIDOGE2 is ERC20 {

    address public AIDOGE = address(0x09E18590E8f76b6Cf471b3cd75fE1A1a9D2B2c2b);
    address public dev = address(0xa7B04185169DBB0f64048a4979008B21eF39D81e);

    constructor() ERC20("AIDOGE2.0", "AIDOGE2.0") {
        _mint(dev, 21_000_000_000_000_000); // 10% dev
        _mint(msg.sender, 126_000_000_000_000_000); // 60% lp
        _mint(address(this), 63_000_000_000_000_000); // 30% airdrop
    }

    mapping(address => bool) public minted;

    function mint() external {
        require(msg.sender == tx.origin, "no contract");
        require(!minted[msg.sender], "minted");
        require(IERC20(AIDOGE).balanceOf(msg.sender) > 1_000_000, "no AIDOGE");
        minted[msg.sender] = true;
        _transfer(address(this), msg.sender, 3_00_000_000_000);
    }
}

