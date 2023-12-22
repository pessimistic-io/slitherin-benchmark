// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./ERC20Votes.sol";

contract EGGOR is ERC20Votes, Ownable {
    address public constant idoAddress =
        0x6670b71E59d4e3EEc140C47dDc075d841cC5d745;
    address public constant platformAddress =
        0x5453B0970698b21f9fcc8991262895BF6c9D1285;
    address public constant airDropAddress =
        0xD0E266b9E67e1544Aa9a6D4894E2f5caA25B7A58;
    address public constant lpAddress =
        0x9ee7C48d5d32cf4ee2b0a15DD58C60103824Fe26;

    uint256 public constant idoAmount = 19_000_000 * 10 ** 18;
    uint256 public constant lpAmount = 1_000_000 * 10 ** 18;
    uint256 public constant platformAmount = 200_000_000 * 10 ** 18;
    uint256 public constant airDropAmount = 50_000_000 * 10 ** 18;
    uint256 public constant lockAmount = 730_000_000 * 10 ** 18;

    mapping(address => bool) public minters;

    constructor(
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) ERC20Permit(name) {
        _mint(idoAddress, idoAmount);
        _mint(platformAddress, platformAmount);
        _mint(airDropAddress, airDropAmount);
        _mint(lpAddress, lpAmount);
        _mint(msg.sender, lockAmount);
    }

    modifier onlyMinter() {
        require(minters[msg.sender], "only minter can do");
        _;
    }

    function addMinter(address _minter) external onlyOwner {
        minters[_minter] = true;
    }

    function removeMinter(address _minter) external onlyOwner {
        delete minters[_minter];
    }

    function mint(uint256 _amount) public onlyMinter {
        _mint(msg.sender, _amount);
    }
}

