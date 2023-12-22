// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.9;
import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract BERRY is ERC20, ERC20Burnable, Pausable, Ownable {
    using SafeMath for uint256;

    address public minter;
    uint256 public MAX_SUPPLY; 

    modifier onlyMinter() {
        require(msg.sender == minter, "Allow only minter");
        _;
    }

    event SetMinter(address minter);
    event AddMinter(address minter);
    event RemoveMinter(address minter);

    constructor(uint256 maxSupply, address treasury, uint256 amount) ERC20("BERRY", "BERRY") {
        require(maxSupply > 0, "Max supply need to be defined");
        MAX_SUPPLY = maxSupply;

        if (amount > 0) {
            require(treasury != address(0), "Treasury need to be defined");
            _mint(treasury, amount);
        }
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setMinter(address _minter) external onlyOwner {
        require(minter == address(0), "Minter has been set");
        require(_minter != address(0), "Minter need to be defined");
        minter = _minter;
        emit SetMinter(_minter);
    }

    function mint(address to, uint256 amount) public onlyMinter {
        require(totalSupply().add(amount) <= MAX_SUPPLY, "Exceed max supply");
        _mint(to, amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}

