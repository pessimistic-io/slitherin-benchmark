pragma solidity ^0.8.7;

import "./ERC20Burnable.sol";
import "./ReentrancyGuard.sol";

contract QB is ERC20Burnable, ReentrancyGuard {
    address private _owner;

    bool public stop;

    bool public adminMinted;

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    constructor() ERC20("QB", "QB") {
        _owner = msg.sender;
    }

    function mint() external payable nonReentrant {
        require(!stop, "Must not stop");
        uint256 mintAmount = msg.value * 10e8;
        _mint(msg.sender, mintAmount);
        payable(_owner).transfer(msg.value);
    }

    function setStop() external onlyOwner {
        stop = true;
    }

    function adminMint() external onlyOwner {
        require(!stop, "Must not stop");
        require(!adminMinted, "Already mint");
        _mint(msg.sender, (totalSupply() * 2) / 10);
        adminMinted = true;
    }
}

