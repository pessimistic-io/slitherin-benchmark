// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC20.sol";
import "./Ownable.sol";

contract Wawa is ERC20, Ownable {
    uint256 public feePercent;
    address public deadwallet = 0x000000000000000000000000000000000000dEaD;
    mapping(address => bool) public whitelist;
    event TransferWithFee(address indexed sender, address indexed recipient, uint256 value, uint256 fee);

    constructor() ERC20("wawa", "WAWA") {
        _mint(msg.sender, 10**11 * 10**decimals()); // 100 billion WAWA tokens
        whitelist[msg.sender]=true;
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        if (whitelist[msg.sender]) {
            _transfer(msg.sender, recipient, amount);
            return true;
        }else{
            uint256 fee = (amount * feePercent) / 100;
            uint256 newAmount = amount - fee;

            _transfer(msg.sender, deadwallet, fee);
            _transfer(msg.sender, recipient, newAmount);

            emit TransferWithFee(msg.sender, recipient, newAmount, fee);

            return true;
        }
    }

    function setFeePercent(uint256 _feePercent) external onlyOwner {
        require(_feePercent <= 100, "Fee is too high");
        feePercent = _feePercent;
    }

    function setWhitelist(address[] calldata addresses, bool flag) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = flag;
        }
    }
}

