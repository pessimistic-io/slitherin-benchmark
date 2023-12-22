// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";

import { Initializable } from "./Initializable.sol";
import { Governable } from "./Governable.sol";

abstract contract InitializableAbstractSingleStrategy is Initializable, Governable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event Deposit(address indexed _asset, address _pToken, uint256 _amount);
    event Withdrawal(address indexed _asset, address _pToken, uint256 _amount);
    event RewardTokenCollected(
        address recipient,
        address rewardToken,
        uint256 amount
    );
    event RewardTokenAddressesUpdated(
        address[] _oldAddresses,
        address[] _newAddresses
    );

    address public vaultAddress;

    // Full list of all assets supported here
    address[] internal assetsMapped;

    // Reward token addresses
    address[] public rewardTokenAddresses;

    // Reserved for future expansion
    int256[98] private _reserved;

    /**
     * @dev Internal initialize function, to set up initial internal state
     * @param _vaultAddress Address of the Vault
     * @param _rewardTokenAddresses Address of reward token for platform
     * @param _assets Addresses of initial supported assets
     */
    function initialize(
        address _vaultAddress,
        address[] calldata _rewardTokenAddresses,
        address[] calldata _assets // Supported Assets in Order
    ) external onlyGovernor initializer {
        InitializableAbstractSingleStrategy._initialize(
            _vaultAddress,
            _rewardTokenAddresses,
            _assets
        );
    }

    function _initialize(
        address _vaultAddress,
        address[] calldata _rewardTokenAddresses,
        address[] memory _assets
    ) internal {
        vaultAddress = _vaultAddress;
        rewardTokenAddresses = _rewardTokenAddresses;
        assetsMapped = _assets;
    }

    /**
     * @dev Verifies that the caller is the Vault.
     */
    modifier onlyVault() {
        require(msg.sender == vaultAddress, "Caller is not the Vault");
        _;
    }

    /**
     * @dev Verifies that the caller is the Vault or Governor.
     */
    modifier onlyVaultOrGovernor() {
        require(
            msg.sender == vaultAddress || msg.sender == governor(),
            "Caller is not the Vault or Governor"
        );
        _;
    }

    /**
     * @dev Set the reward token addresses.
     * @param _rewardTokenAddresses Address array of the reward token
     */
    function setRewardTokenAddresses(address[] calldata _rewardTokenAddresses)
        external
        onlyGovernor
    {
        for (uint256 i = 0; i < _rewardTokenAddresses.length; i++) {
            require(
                _rewardTokenAddresses[i] != address(0),
                "Can not set an empty address as a reward token"
            );
        }

        emit RewardTokenAddressesUpdated(
            rewardTokenAddresses,
            _rewardTokenAddresses
        );
        rewardTokenAddresses = _rewardTokenAddresses;
    }

    /**
     * @dev Get the reward token addresses.
     * @return address[] the reward token addresses.
     */
    function getRewardTokenAddresses()
        external
        view
        returns (address[] memory)
    {
        return rewardTokenAddresses;
    }

    /***************************************
                 Abstract
    ****************************************/
    /**
    * @dev Collect accumulated reward token and send to Vault.
    */
    function collectRewardTokens() external virtual returns (uint256);    

    /**
     * @dev Deposit an amount of asset into the platform
     * @param _amount              Unit of asset to deposit
     */
    function deposit(uint256 _amount) external virtual;

    /**
     * @dev Withdraw an amount of asset from the platform.
     * @param _recipient         Address to which the asset should be sent
     * @param _amount            Units of assets to withdraw
     */
    function withdraw(
        address _recipient,
        uint256 _amount
    ) external virtual;

    /**
     * @dev Withdraw all assets from strategy sending assets to Vault.
     */
    function withdrawAll() external virtual;

    /**
     * @dev Get the total primary stable value held in the platform.
     *      This includes any interest that was generated since depositing.
     * @return balance    Total value of the asset in the platform
     */
    function balance()
        external
        view
        virtual
        returns (uint256);

    /**
    * @dev Get the LP token count of the startegy
    * @return uint256 - LP balance of strategy
    */
    function lpBalance() external view virtual returns (uint256);
    
    function health() external view virtual returns (uint256);
}

