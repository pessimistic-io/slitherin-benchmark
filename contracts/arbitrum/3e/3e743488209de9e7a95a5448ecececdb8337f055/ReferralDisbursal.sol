// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.21;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Address.sol";
import {TreasuryContract} from "./ITreasury.sol";

contract ReferralDisbursal is Initializable, UUPSUpgradeable {
    using Address for address;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    bool private isReferralDistribution;
    address public treasuryContractAddress;
    IERC20Upgradeable public rewardToken;

    event EmergencyWithdrawn(
        IERC20Upgradeable tokenAddress,
        address to,
        uint256 amount
    );

    event RewardDistribution(address receiver, uint amount);

    struct Affiliatee {
        address receiver;
        uint amount;
    }
    event UpdatedIsReferralDistribution(bool status);
    event UpdatedRewardToken(address rewardToken);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier isAdmin() {
        require(
            TreasuryContract(treasuryContractAddress).isAdmin(msg.sender),
            "Not authorized"
        );
        _;
    }

    modifier isReferralDisburser() {
        require(
            TreasuryContract(treasuryContractAddress).isReferralDisburser(
                msg.sender
            ),
            "Not authorized"
        );
        _;
    }

    /**
     * @notice Initialize contract, sets treasury and reward address and makes the referral distribution enabled.
     */
    function initialize(
        address _treasuryContractAddress,
        IERC20Upgradeable _rewardToken
    ) public initializer {
        isReferralDistribution = true;
        treasuryContractAddress = _treasuryContractAddress;
        rewardToken = _rewardToken;
    }

    /**
     * @notice Function to update isReferralDistribution,caller must have Admin role.
     */
    function updateReferralDisbursalStatus() external isAdmin {
        isReferralDistribution = !isReferralDistribution;
        emit UpdatedIsReferralDistribution(isReferralDistribution);
    }

    /**
     * @notice Function to update the address of the reward token.
     * @param _rewardToken The new address of the reward token.
     */
    function updateAcceptedTokens(address _rewardToken) external isAdmin {
        require(
            _rewardToken.isContract(),
            "Please provide valid token address"
        );
        rewardToken = IERC20Upgradeable(_rewardToken);
        emit UpdatedRewardToken(_rewardToken);
    }

    /**
     * @notice Function to provide functionality for distributing ERC20 token among multiple affiliatee addresses as per the input,
     * caller must have ReferralDisburser role.
     * @param  affiliateeInfo array of Affiliatee addresses.
     */
    function distributeRewards(
        Affiliatee[] memory affiliateeInfo
    ) external isReferralDisburser {
        require(isReferralDistribution, "Distribution is disabled");
        for (uint8 i = 0; i < affiliateeInfo.length; i++) {
            rewardToken.safeTransfer(
                affiliateeInfo[i].receiver,
                affiliateeInfo[i].amount
            );
            emit RewardDistribution(
                affiliateeInfo[i].receiver,
                affiliateeInfo[i].amount
            );
        }
    }

    /**
     * @notice Function to provide functionality for emergency withdraw ERC20 token from the contract,
     * caller must have Admin role.
     * @param  _tokenAddress Address of ERC20 token to withdraw.
     * @param  _to Address where the withdrawn tokens are to be transferred.
     * @param  _amount  Amount of token to withdraw.
     */
    function emergencyWithdraw(
        IERC20Upgradeable _tokenAddress,
        address _to,
        uint256 _amount
    ) external isAdmin {
        _tokenAddress.safeTransfer(_to, _amount);
        emit EmergencyWithdrawn(_tokenAddress, _to, _amount);
    }

    /**
     * @notice Function to provide functionality for upgrading the contract by adding new implementation contract,
     * caller must have Admin role.
     * @param   _newImplementation.
     */
    function _authorizeUpgrade(
        address _newImplementation
    ) internal override isAdmin {}
}

