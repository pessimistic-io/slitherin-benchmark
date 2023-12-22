// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./IERC20.sol";

contract AIDOGE2 is ERC20 {

    address public AIDOGE = address(0x09E18590E8f76b6Cf471b3cd75fE1A1a9D2B2c2b);
    address public dev = address(0xa7B04185169DBB0f64048a4979008B21eF39D81e);

    constructor() ERC20("AIDOGE2.0", "AIDOGE2.0") {
        _mint(dev, 10_500_000_000_000_000 ether); // 5% dev
        _mint(msg.sender, 63_000_000_000_000_000 ether); // 30% lp
        _mint(address(this), 136_500_000_000_000_000 ether); // 65% airdrop
    }

    mapping(address => bool) public minted;

    function mint() external {
        require(msg.sender == tx.origin, "no contract");
        require(!minted[msg.sender], "minted");
        require(IERC20(AIDOGE).balanceOf(msg.sender) > 1_000_000 * 1e6, "no AIDOGE");
        require(balanceOf(address(this)) > 0, "no AIDOGE2.0");
        minted[msg.sender] = true;
        _transfer(address(this), msg.sender, 3_000_000_000_000 ether);
    }
}

