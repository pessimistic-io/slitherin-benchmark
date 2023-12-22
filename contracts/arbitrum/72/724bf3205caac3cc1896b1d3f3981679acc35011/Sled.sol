//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "./ERC20.sol";
import "./IERC165.sol";
import "./ISled.sol";
import "./Ownable.sol";

contract Sled is ERC20, ISled, Ownable {
    address public minter;

    constructor() ERC20("ArbiSled", "SLED") {}

    function mint(address _to, uint256 _amount) external override onlyMinter {
        _mint(_to, _amount);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    modifier onlyMinter() {
        require(
            msg.sender == minter || msg.sender == owner(),
            "Only minter can call this"
        );
        _;
    }
}

