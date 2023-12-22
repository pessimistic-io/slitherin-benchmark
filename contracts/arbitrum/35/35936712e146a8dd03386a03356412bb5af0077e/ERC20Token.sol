pragma solidity ^0.5.16;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Detailed.sol";
import "./ERC20Mintable.sol";
import "./ERC20Pausable.sol";
import "./Ownable.sol";
import "./Initializable.sol";

contract ERC20Token is
    Initializable,
    ERC20Burnable,
    ERC20Mintable,
    ERC20Pausable,
    ERC20Detailed,
    Ownable
{
    address private tokenOwner;

    function() external payable {}

    function initialize(
        string calldata name,
        string calldata symbol,
        uint8 decimals,
        address _tokenOwner
    ) external initializer {
        Ownable.initialize(msg.sender);

        tokenOwner = _tokenOwner;

        ERC20Detailed.initialize(name, symbol, decimals);

        ERC20Mintable.initialize(address(this));
        _removeMinter(address(this));
        _addMinter(tokenOwner);

        ERC20Pausable.initialize(address(this));
        _removePauser(address(this));
        _addPauser(tokenOwner);

        _transferOwnership(tokenOwner);
    }

    function setOwner(address _tokenOwner) external onlyOwner {
        _removeMinter(tokenOwner);
        _removePauser(tokenOwner);

        tokenOwner = _tokenOwner;
        _addMinter(_tokenOwner);
        _addPauser(_tokenOwner);
        _transferOwnership(_tokenOwner);
    }
}

