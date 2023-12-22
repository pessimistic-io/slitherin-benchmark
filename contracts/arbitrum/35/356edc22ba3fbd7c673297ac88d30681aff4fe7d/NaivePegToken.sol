// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ERC20 } from "./ERC20.sol";
import { Ownable } from "./Ownable.sol";

contract NaivePegToken is ERC20, Ownable {
    address public minter;
    uint8 internal _decimals;
    uint256 public maxSupply;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 maxSupply_,
        address minter_
    ) ERC20(name_, symbol_) Ownable() {
        minter = minter_;
        _decimals = decimals_;
        maxSupply = maxSupply_;
    }

    modifier onlyMinter() {
        require(msg.sender == minter, "Only minter can call this function");
        _;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setMaxSupply(uint256 maxSupply_) public onlyOwner {
        maxSupply = maxSupply_;
    }

    function setMinter(address minter_) public onlyOwner {
        require(minter_ != address(0), "Cant set minter to zero address");
        minter = minter_;
    }

    function mint(address to_, uint256 amount_) external onlyMinter {
        require(amount_ > 0, "Nothing to mint");
        require(totalSupply() + amount_ <= maxSupply, "Max supply exceeded");

        _mint(to_, amount_);
    }

    /**
     * @dev Burns `amount` tokens from `account`
     * @dev For accounting purposes, as a peg token, users are not allowed to burn it themselves.
     */
    function burnFrom(address account_, uint256 amount_) external onlyMinter {
        _burn(account_, amount_);
    }
}

