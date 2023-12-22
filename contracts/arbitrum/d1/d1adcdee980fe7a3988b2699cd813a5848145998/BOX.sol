pragma solidity ^0.8.7;

import "./ERC20Burnable.sol";
import "./ReentrancyGuard.sol";
import "./AccessControlEnumerable.sol";

contract BOX is ERC20Burnable, ReentrancyGuard, AccessControlEnumerable {
    uint256 mintNum;

    mapping(address => bool) minted;

    uint256 public maxSupply;

    bytes32 public constant MINT_ROLE = bytes32(uint256(1));

    constructor() ERC20("BOX", "BOX") {
        _setupRole(AccessControl.DEFAULT_ADMIN_ROLE, _msgSender());
        maxSupply = 1e36;
    }

    function boxFanMint() external payable nonReentrant {
        require(!minted[_msgSender()]);
        require(mintNum < 500);
        minted[_msgSender()] = true;
        _mint(_msgSender(), (maxSupply - totalSupply()) / 50000);
        mintNum++;
    }

    function mint(
        address _address,
        uint256 _amount
    ) external onlyRole(MINT_ROLE) {
        _mint(_address, _amount);
    }
}

