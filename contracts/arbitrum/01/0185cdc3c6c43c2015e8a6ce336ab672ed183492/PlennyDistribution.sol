// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./SafeMath.sol";
import "./SafeERC20Upgradeable.sol";
import "./UpgradeableBeacon.sol";
import "./IBasePlennyERC20.sol";
import "./ClonableBeaconProxy.sol";

/// @title  PlennyDistribution
/// @notice Contains the logic for the initial token generation and distribution.
/// @dev    Uses an upgradable beacon pattern for managing the upgradability of the PlennyERC20 token
contract PlennyDistribution is UpgradeableBeacon {
    using SafeMath for uint;
    using SafeERC20Upgradeable for IBasePlennyERC20;

    /// @dev stores the token address
    address internal plennyToken;

    /// An event emitted when the Plenny token is created
    event PlennyERC20Deployed(address token);

    /* solhint-disable-next-line no-empty-blocks */
    /// @notice Constructs the smart contract by providing the beacon address.
    /// @param  implementation_ proxy implementation
    constructor(address implementation_) public UpgradeableBeacon(implementation_) {

    }

    /// @notice Creates the PlennyERC20 token contract using beacon proxy. Called only once by the owner.
    /// @param  userSalt random salt
    function createToken(bytes32 userSalt) external onlyOwner {

        require(plennyToken == address(0), "ALREADY_CREATED");

        bytes32 salt = keccak256(abi.encodePacked(msg.sender, userSalt));
        ClonableBeaconProxy createdContract = new ClonableBeaconProxy{ salt:salt }();

        plennyToken = address(createdContract);

        emit PlennyERC20Deployed(plennyToken);
    }

    /// @notice Initializes the data of the plenny token. Called only once by the owner.
    /// @param  _data token data
    function tokenInit(bytes memory _data) external onlyOwner {

        require(plennyToken != address(0), "NOT_CREATED");
        IBasePlennyERC20(plennyToken).initialize(msg.sender, _data);
    }

    /// @notice Mints the initial token supply to the sender's address. Called only once by the owner.
    /// @param  _plennyTotalSupply initial token supply
    function tokenMint(uint256 _plennyTotalSupply) external onlyOwner {

        require(plennyToken != address(0), "NOT_CREATED");
        require(plennyTotalSupply() == 0, "ALREADY_MINT");
        IBasePlennyERC20(plennyToken).mint(msg.sender, _plennyTotalSupply);
    }

    /// @notice Gets the plenny token address, created by this contact.
    /// @return address plenny token address
    function getPlennyTokenAddress() external view returns (address) {
        return plennyToken;
    }

    /// @notice Gets the plenny total supply.
    /// @return uint256 token supply
    function plennyTotalSupply() public view returns (uint256) {
        return IBasePlennyERC20(plennyToken).totalSupply();
    }
}

