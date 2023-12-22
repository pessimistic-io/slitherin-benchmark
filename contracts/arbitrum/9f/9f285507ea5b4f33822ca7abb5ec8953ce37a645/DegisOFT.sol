// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "./OFT.sol";

import "./Ownable.sol";

contract DegisOFT is Ownable, OFT {
    // List of all minters
    mapping(address => bool) public isMinter;

    // List of all burners
    mapping(address => bool) public isBurner;

    event MinterAdded(address newMinter);
    event MinterRemoved(address oldMinter);

    event BurnerAdded(address newBurner);
    event BurnerRemoved(address oldBurner);

    event Mint(address indexed account, uint256 amount);
    event Burn(address indexed account, uint256 amount);

    constructor(
        address _layerzeroEndpoint
    ) OFT("DegisToken", "DEG", _layerzeroEndpoint) {
        isMinter[msg.sender] = true;
    }

    /**
     *@notice Check if the msg.sender is in the minter list
     */
    modifier validMinter(address _sender) {
        require(isMinter[_sender], "Invalid minter");
        _;
    }

    /**
     * @notice Check if the msg.sender is in the burner list
     */
    modifier validBurner(address _sender) {
        require(isBurner[_sender], "Invalid burner");
        _;
    }

    // ---------------------------------------------------------------------------------------- //
    // *********************************** Admin Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Add a new minter into the minterList
     * @param _newMinter Address of the new minter
     */
    function addMinter(address _newMinter) external onlyOwner {
        require(!isMinter[_newMinter], "Already a minter");

        isMinter[_newMinter] = true;

        emit MinterAdded(_newMinter);
    }

    /**
     * @notice Remove a minter from the minterList
     * @param _oldMinter Address of the minter to be removed
     */
    function removeMinter(address _oldMinter) external onlyOwner {
        require(isMinter[_oldMinter], "Not a minter");

        isMinter[_oldMinter] = false;

        emit MinterRemoved(_oldMinter);
    }

    /**
     * @notice Add a new burner into the burnerList
     * @param _newBurner Address of the new burner
     */
    function addBurner(address _newBurner) external onlyOwner {
        require(!isBurner[_newBurner], "Already a burner");

        isBurner[_newBurner] = true;

        emit BurnerAdded(_newBurner);
    }

    /**
     * @notice Remove a minter from the minterList
     * @param _oldBurner Address of the minter to be removed
     */
    function removeBurner(address _oldBurner) external onlyOwner {
        require(isMinter[_oldBurner], "Not a burner");

        isBurner[_oldBurner] = false;

        emit BurnerRemoved(_oldBurner);
    }

    /**
     * @notice Mint tokens
     * @param _account Receiver's address
     * @param _amount Amount to be minted
     */
    function mintDegis(
        address _account,
        uint256 _amount
    ) internal validMinter(msg.sender) {
        _mint(_account, _amount); // ERC20 method with an event
        emit Mint(_account, _amount);
    }

    /**
     * @notice Burn tokens
     * @param _account address
     * @param _amount amount to be burned
     */
    function burnDegis(
        address _account,
        uint256 _amount
    ) internal validBurner(msg.sender) {
        _burn(_account, _amount);
        emit Burn(_account, _amount);
    }
}

