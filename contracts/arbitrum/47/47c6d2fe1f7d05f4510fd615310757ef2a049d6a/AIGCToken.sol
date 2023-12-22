// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./ERC20.sol";

/// @title AIGCToken Contract
contract AIGCToken is Ownable, ERC20, Pausable {
    using SafeMath for uint256;
    bool private initialized;

    //events
    event eveMint(address indexed to, uint256 indexed value);

    event AddMinter(address minter);
    event DelMinter(address minter);

    // for minters
    mapping(address => bool) public _minters;

    /**
     * CONSTRUCTOR
     *
     * @dev Initialize the Token
     */
    constructor() ERC20("aigc.defusion.ai", "AIGC") {}

    function initialize(
        address _owner
    ) external {
        require(!initialized, "initialize: Already initialized!");
        _transferOwnership(_owner);
        initialized = true;
    }
    /**
     * @dev for mint function
     */
    function mint(address account, uint256 amount) external {
        require(_minters[msg.sender], "not minter");
        _mint(account, amount);
        emit eveMint(account, amount);
    }

    function pause() external onlyOwner {
        super._pause();
    }

    function unpause() external onlyOwner {
        super._unpause();
    }

    function addMinter(address _minter) external onlyOwner {
        require(!_minters[_minter], "is minter");
        _minters[_minter] = true;
        emit AddMinter(_minter);
    }

    function removeMinter(address _minter) external onlyOwner {
        require(_minters[_minter], "not is minter");
        _minters[_minter] = false;
        emit DelMinter(_minter);
    }

    /**
     * @dev Transfer tokens with fee
     * @param from address The address which you want to send tokens from
     * @param to address The address which you want to transfer to
     * @param value uint256s the amount of tokens to be transferred
     */
    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal override whenNotPaused {
        super._transfer(from, to, value);
    }

    function name() public view virtual override returns (string memory) {
        return "aigc.defusion.ai";
    }

    function symbol() public view virtual override returns (string memory) {
        return "AIGC";
    }
}

