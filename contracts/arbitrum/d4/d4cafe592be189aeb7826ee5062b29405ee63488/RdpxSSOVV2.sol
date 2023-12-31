//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**                             .                    .                             
                           .'.                    .'.                           
                         .;:.                      .;:.                         
                       .:o:.                        .;l:.                       
                     .:dd,                            ,od:.                     
                   .:dxo'                              .lxd:.                   
                 .:dkxc.                                .:xkd:.                 
               .:dkkx:.                                  .;dkkd:.               
              .ckkkkxl:,'..                            ..':dkkkkl.              
               'codxxkkkxxdol,                     .,cldxkkkxdoc,               
                  ..',;coxkkkl.                  .;dxkxdol:;'..                 
                       .cxkxl.                   ;dkxl,..                       
                      .:xxxc.                   .cxxd'                          
                      ;dxd:.    ;c,.            .:dxo'                          
                     .lddc.    .cdoc.            'odd:.                         
                     .loo;.     .clol'           .;ool,                         
                     .:loc,.      ..'.            .:loc'                        
                      .,cllc;'.                    .;llc'                       
                        .';cccc:'.                  .;cc:.                      
                           ..,;::;'                  .;::;.                     
                              .';::,.                 .;:;.                     
                                .,;;,.                .;;;.                     
                                  .,,,'..            .,,,'.                     
                                   ..',,,'..      ..'','.                       
                                     ...'''''.....'''...                        
                                         ............                           
                            DOPEX SINGLE STAKING OPTION VAULT
            Mints covered calls while farming yield on single sided DPX staking farm                                                           
*/

// Libraries
import {Strings} from "./Strings.sol";
import {Clones} from "./Clones.sol";
import {BokkyPooBahsDateTimeLibrary} from "./BokkyPooBahsDateTimeLibrary.sol";
import {SafeERC20} from "./SafeERC20.sol";

// Contracts
import {ERC20PresetMinterPauserUpgradeable} from "./ERC20PresetMinterPauserUpgradeable.sol";
import {Pausable} from "./Pausable.sol";
import {ContractWhitelist} from "./ContractWhitelist.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {IVolatilityOracle} from "./IVolatilityOracle.sol";
import {IStakingRewards} from "./IStakingRewards.sol";
import {IOptionPricing} from "./IOptionPricing.sol";
import {IERC20SSOV} from "./IERC20SSOV.sol";
import {IFeeStrategy} from "./IFeeStrategy.sol";

interface IPriceOracle {
    function getPriceInUSD() external view returns (uint256);
}

contract RdpxSSOVV2 is ContractWhitelist, Pausable, IERC20SSOV {
    using BokkyPooBahsDateTimeLibrary for uint256;
    using Strings for uint256;
    using SafeERC20 for IERC20;

    /// @dev ERC20PresetMinterPauserUpgradeable implementation address
    address public immutable erc20Implementation;

    /// @dev Current epoch for ssov
    uint256 public currentEpoch;

    /// @dev Expire delay tolerance
    uint256 public expireDelayTolerance = 5 minutes;

    /// @dev The list of contract addresses the contract uses
    mapping(bytes32 => address) public addresses;

    /// @dev epoch => the epoch start time
    mapping(uint256 => uint256) public epochStartTimes;

    /// @notice Is epoch expired
    /// @dev epoch => whether the epoch is expired
    mapping(uint256 => bool) public isEpochExpired;

    /// @notice Is vault ready for next epoch
    /// @dev epoch => whether the vault is ready (boostrapped)
    mapping(uint256 => bool) public isVaultReady;

    /// @dev Mapping of strikes for each epoch
    mapping(uint256 => uint256[]) public epochStrikes;

    /// @dev Mapping of (epoch => (strike => tokens))
    mapping(uint256 => mapping(uint256 => address)) public epochStrikeTokens;

    /// @notice Total epoch deposits for specific strikes
    /// @dev mapping (epoch => (strike => deposits))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochStrikeDeposits;

    /// @notice Total epoch deposits across all strikes
    /// @dev mapping (epoch => deposits)
    mapping(uint256 => uint256) public totalEpochDeposits;

    /// @notice Total epoch deposits for specific strikes including premiums and rewards
    /// @dev mapping (epoch => (strike => deposits))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochStrikeBalance;

    /// @notice Total epoch deposits across all strikes including premiums and rewards
    /// @dev mapping (epoch => deposits)
    mapping(uint256 => uint256) public totalEpochBalance;

    /// @notice Epoch deposits by user for each strike
    /// @dev mapping (epoch => (abi.encodePacked(user, strike) => user deposits))
    mapping(uint256 => mapping(bytes32 => uint256)) public userEpochDeposits;

    /// @notice Epoch rDPX balance per strike after accounting for rewards
    /// @dev mapping (epoch => (strike => balance))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochStrikeRdpxBalance;

    /// @notice Epoch DPX balance per strike after accounting for rewards
    /// @dev mapping (epoch => (strike => balance))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochStrikeDpxBalance;

    // Calls purchased for each strike in an epoch
    /// @dev mapping (epoch => (strike => calls purchased))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochCallsPurchased;

    /// @notice Calls purchased by user for each strike
    /// @dev mapping (epoch => (abi.encodePacked(user, strike) => user calls purchased))
    mapping(uint256 => mapping(bytes32 => uint256))
        public userEpochCallsPurchased;

    /// @notice Premium collected per strike for an epoch
    /// @dev mapping (epoch => (strike => premium))
    mapping(uint256 => mapping(uint256 => uint256)) public totalEpochPremium;

    /// @notice User premium collected per strike for an epoch
    /// @dev mapping (epoch => (abi.encodePacked(user, strike) => user premium))
    mapping(uint256 => mapping(bytes32 => uint256)) public userEpochPremium;

    /// @dev epoch => settlement price
    mapping(uint256 => uint256) public settlementPrices;

    /*==== EVENTS ====*/

    event ExpireDelayToleranceUpdate(uint256 expireDelayTolerance);

    event AddressSet(bytes32 indexed name, address indexed destination);

    event EmergencyWithdraw(
        address sender,
        uint256 dpxWithdrawn,
        uint256 rdpxWithdrawn
    );

    event NewStrike(uint256 epoch, uint256 strike);

    event Bootstrap(uint256 epoch);

    event NewDeposit(
        uint256 epoch,
        uint256 strike,
        uint256 amount,
        address user,
        address sender
    );

    event NewPurchase(
        uint256 epoch,
        uint256 strike,
        uint256 amount,
        uint256 premium,
        uint256 fee,
        address user,
        address sender
    );

    event NewSettle(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 amount,
        uint256 pnl
    );

    event Compound(
        uint256 epoch,
        uint256 rewards,
        uint256 oldBalance,
        uint256 newBalance
    );

    event NewWithdraw(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 amount,
        uint256 rdpxAmount
    );

    /*==== CONSTRUCTOR ====*/

    constructor(
        address _dpx,
        address _rdpx,
        address _stakingRewards,
        address _optionPricing,
        address _rdpxPriceOracle,
        address _volatilityOracle,
        address _feeDistributor,
        address _feeStrategy
    ) {
        require(_dpx != address(0), 'E1');
        require(_rdpx != address(0), 'E1');
        require(_stakingRewards != address(0), 'E1');
        require(_optionPricing != address(0), 'E1');
        require(_rdpxPriceOracle != address(0), 'E1');
        require(_feeStrategy != address(0), 'E1');

        addresses['FeeDistributor'] = _feeDistributor;
        addresses['DPX'] = _dpx;
        addresses['rDPX'] = _rdpx;
        addresses['StakingRewards'] = _stakingRewards;
        addresses['OptionPricing'] = _optionPricing;
        addresses['RdpxPriceOracle'] = _rdpxPriceOracle;
        addresses['VolatilityOracle'] = _volatilityOracle;
        addresses['FeeStrategy'] = _feeStrategy;
        addresses['Governance'] = msg.sender;

        erc20Implementation = address(new ERC20PresetMinterPauserUpgradeable());

        // Max approve to stakingRewards
        IERC20(getAddress('rDPX')).safeApprove(
            getAddress('StakingRewards'),
            type(uint256).max
        );
    }

    /*==== SETTER METHODS ====*/

    /// @notice Pauses the vault for emergency cases
    /// @dev Can only be called by governance
    /// @return Whether it was successfully paused
    function pause() external onlyGovernance returns (bool) {
        _pause();
        _updateFinalEpochBalances(false);
        return true;
    }

    /// @notice Unpauses the vault
    /// @dev Can only be called by governance
    /// @return Whether it was successfully unpaused
    function unpause() external onlyGovernance returns (bool) {
        _unpause();
        return true;
    }

    /// @notice Updates the delay tolerance for the expiry epoch function
    /// @dev Can only be called by governance
    /// @return Whether it was successfully updated
    function updateExpireDelayTolerance(uint256 _expireDelayTolerance)
        external
        onlyGovernance
        returns (bool)
    {
        expireDelayTolerance = _expireDelayTolerance;
        emit ExpireDelayToleranceUpdate(_expireDelayTolerance);
        return true;
    }

    /// @notice Sets (adds) a list of addresses to the address list
    /// @param names Names of the contracts
    /// @param destinations Addresses of the contract
    /// @return Whether the addresses were set
    function setAddresses(
        bytes32[] calldata names,
        address[] calldata destinations
    ) external onlyOwner returns (bool) {
        require(names.length == destinations.length, 'E2');
        for (uint256 i = 0; i < names.length; i++) {
            bytes32 name = names[i];
            address destination = destinations[i];
            addresses[name] = destination;
            emit AddressSet(name, destination);
        }
        return true;
    }

    /*==== METHODS ====*/

    /// @notice Transfers all funds to msg.sender
    /// @dev Can only be called by governance
    /// @return Whether emergency withdraw was successful
    function emergencyWithdraw()
        external
        onlyGovernance
        whenPaused
        returns (bool)
    {
        IERC20 dpx = IERC20(getAddress('DPX'));
        IERC20 rdpx = IERC20(getAddress('rDPX'));

        uint256 dpxBalance = dpx.balanceOf(address(this));
        uint256 rdpxBalance = rdpx.balanceOf(address(this));

        dpx.safeTransfer(msg.sender, dpxBalance);
        rdpx.safeTransfer(msg.sender, rdpxBalance);

        emit EmergencyWithdraw(msg.sender, dpxBalance, rdpxBalance);

        return true;
    }

    /// @notice Sets the current epoch as expired.
    /// @return Whether expire was successful
    function expireEpoch()
        external
        whenNotPaused
        isEligibleSender
        returns (bool)
    {
        require(!isEpochExpired[currentEpoch], 'E3');
        (, uint256 epochExpiry) = getEpochTimes(currentEpoch);
        require((block.timestamp >= epochExpiry), 'E4');
        require(block.timestamp <= epochExpiry + expireDelayTolerance, 'E23');

        settlementPrices[currentEpoch] = getUsdPrice();

        _updateFinalEpochBalances(true);

        isEpochExpired[currentEpoch] = true;

        return true;
    }

    /// @notice Sets the current epoch as expired.
    /// @return Whether expire was successful
    function expireEpoch(uint256 settlementPrice)
        external
        onlyGovernance
        whenNotPaused
        returns (bool)
    {
        require(!isEpochExpired[currentEpoch], 'E3');
        (, uint256 epochExpiry) = getEpochTimes(currentEpoch);
        require((block.timestamp > epochExpiry + expireDelayTolerance), 'E4');

        settlementPrices[currentEpoch] = settlementPrice;

        _updateFinalEpochBalances(true);

        isEpochExpired[currentEpoch] = true;

        return true;
    }

    /// @dev Updates the final epoch DPX/rDPX balances per strike of the vault
    /// @param accountPremiums Should the fn account for premiums
    function _updateFinalEpochBalances(bool accountPremiums) internal {
        IStakingRewards stakingRewards = IStakingRewards(
            getAddress('StakingRewards')
        );

        IERC20 dpx = IERC20(getAddress('DPX'));
        IERC20 rdpx = IERC20(getAddress('rDPX'));

        if (stakingRewards.balanceOf(address(this)) > 0) {
            // Unstake all tokens from previous epoch
            stakingRewards.withdraw(stakingRewards.balanceOf(address(this)));
        }

        uint256 totalDpxRewardsClaimed = dpx.balanceOf(address(this));
        uint256 totalRdpxRewardsClaimed = rdpx.balanceOf(address(this));

        // Claim DPX and rDPX rewards
        stakingRewards.getReward(2);

        totalDpxRewardsClaimed =
            dpx.balanceOf(address(this)) -
            totalDpxRewardsClaimed;
        totalRdpxRewardsClaimed =
            rdpx.balanceOf(address(this)) -
            totalRdpxRewardsClaimed;

        if (totalEpochBalance[currentEpoch] > 0) {
            uint256[] memory strikes = epochStrikes[currentEpoch];

            for (uint256 i = 0; i < strikes.length; i++) {
                // rDPX rewards for each strike
                uint256 rdpxRewards = (totalRdpxRewardsClaimed *
                    totalEpochStrikeBalance[currentEpoch][strikes[i]]) /
                    totalEpochBalance[currentEpoch];

                // PnL from ssov option settlements
                uint256 settlement = calculatePnl(
                    settlementPrices[currentEpoch],
                    strikes[i],
                    totalEpochCallsPurchased[currentEpoch][strikes[i]]
                );

                // Update final dpx and rdpx balances for epoch and strike
                totalEpochStrikeRdpxBalance[currentEpoch][strikes[i]] +=
                    totalEpochStrikeDeposits[currentEpoch][strikes[i]] +
                    rdpxRewards -
                    settlement;
                if (accountPremiums) {
                    totalEpochStrikeRdpxBalance[currentEpoch][
                        strikes[i]
                    ] += totalEpochPremium[currentEpoch][strikes[i]];
                }

                totalEpochStrikeDpxBalance[currentEpoch][strikes[i]] =
                    (totalDpxRewardsClaimed *
                        totalEpochStrikeBalance[currentEpoch][strikes[i]]) /
                    totalEpochBalance[currentEpoch];
            }
        }
    }

    /**
     * @notice Bootstraps a new epoch and mints option tokens equivalent to user deposits for the epoch
     * @return Whether bootstrap was successful
     */
    function bootstrap() external onlyOwner whenNotPaused returns (bool) {
        uint256 nextEpoch = currentEpoch + 1;
        require(!isVaultReady[nextEpoch], 'E5');
        require(epochStrikes[nextEpoch].length > 0, 'E6');

        if (currentEpoch > 0) {
            // Previous epoch must be expired
            require(isEpochExpired[currentEpoch], 'E7');
        }

        for (uint256 i = 0; i < epochStrikes[nextEpoch].length; i++) {
            uint256 strike = epochStrikes[nextEpoch][i];
            string memory name = concatenate('rDPX-CALL', strike.toString());
            name = concatenate(name, '-EPOCH-');
            name = concatenate(name, (nextEpoch).toString());
            // Create doTokens representing calls for selected strike in epoch
            ERC20PresetMinterPauserUpgradeable _erc20 = ERC20PresetMinterPauserUpgradeable(
                    Clones.clone(erc20Implementation)
                );
            _erc20.initialize(name, name);
            epochStrikeTokens[nextEpoch][strike] = address(_erc20);
            // Mint tokens equivalent to deposits for strike in epoch
            _erc20.mint(
                address(this),
                totalEpochStrikeDeposits[nextEpoch][strike]
            );
        }

        // Mark vault as ready for epoch
        isVaultReady[nextEpoch] = true;
        // Increase the current epoch
        currentEpoch = nextEpoch;

        emit Bootstrap(nextEpoch);

        return true;
    }

    /**
     * @notice Sets strikes for next epoch
     * @param strikes Strikes to set for next epoch
     * @return Whether strikes were set
     */
    function setStrikes(uint256[] memory strikes)
        external
        onlyOwner
        whenNotPaused
        returns (bool)
    {
        uint256 nextEpoch = currentEpoch + 1;

        require(totalEpochDeposits[nextEpoch] == 0, 'E8');

        if (currentEpoch > 0) {
            (, uint256 epochExpiry) = getEpochTimes(currentEpoch);
            require((block.timestamp > epochExpiry), 'E9');
        }

        // Set the next epoch strikes
        epochStrikes[nextEpoch] = strikes;
        // Set the next epoch start time
        epochStartTimes[nextEpoch] = block.timestamp;

        for (uint256 i = 0; i < strikes.length; i++)
            emit NewStrike(nextEpoch, strikes[i]);
        return true;
    }

    /**
     * @notice Deposits rdpx into the ssov to mint options in the next epoch for selected strikes
     * @param strikeIndex Index of strike
     * @param amount Amout of rDPX to deposit
     * @param user Address of the user to deposit for
     * @return Whether deposit was successful
     */
    function deposit(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) public whenNotPaused isEligibleSender returns (bool) {
        uint256 nextEpoch = currentEpoch + 1;

        if (currentEpoch > 0) {
            require(
                isEpochExpired[currentEpoch] && !isVaultReady[nextEpoch],
                'E19'
            );
        }

        require(strikeIndex < epochStrikes[nextEpoch].length, 'E10');
        require(amount > 0, 'E11');

        uint256 strike = epochStrikes[nextEpoch][strikeIndex];
        require(strike != 0, 'E12');

        bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

        // Transfer rDPX from msg.sender (maybe different from user param) to ssov
        IERC20(getAddress('rDPX')).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );

        // Add to user epoch deposits
        userEpochDeposits[nextEpoch][userStrike] += amount;
        // Add to total epoch strike deposits
        totalEpochStrikeDeposits[nextEpoch][strike] += amount;
        // Add to total epoch deposits
        totalEpochDeposits[nextEpoch] += amount;
        // Add to total epoch strike deposits
        totalEpochStrikeBalance[nextEpoch][strike] += amount;
        // Add to total epoch deposits
        totalEpochBalance[nextEpoch] += amount;
        // Deposit into staking rewards
        IStakingRewards(getAddress('StakingRewards')).stake(amount);

        emit NewDeposit(nextEpoch, strike, amount, user, msg.sender);

        return true;
    }

    /**
     * @notice Deposit rDPX multiple times
     * @param strikeIndices Indices of strikes to deposit into
     * @param amounts Amount of rDPX to deposit into each strike index
     * @param user Address of the user to deposit for
     * @return Whether deposits went through successfully
     */
    function depositMultiple(
        uint256[] memory strikeIndices,
        uint256[] memory amounts,
        address user
    ) external whenNotPaused returns (bool) {
        require(strikeIndices.length == amounts.length, 'E2');

        for (uint256 i = 0; i < strikeIndices.length; i++)
            deposit(strikeIndices[i], amounts[i], user);
        return true;
    }

    /**
     * @notice Purchases calls for the current epoch
     * @param strikeIndex Strike index for current epoch
     * @param amount Amount of calls to purchase
     * @param user User to purchase options for
     * @return Whether purchase was successful
     */
    function purchase(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) external whenNotPaused isEligibleSender returns (uint256, uint256) {
        require(isVaultReady[currentEpoch], 'E20');
        require(strikeIndex < epochStrikes[currentEpoch].length, 'E10');
        require(amount > 0, 'E11');

        uint256 strike = epochStrikes[currentEpoch][strikeIndex];
        require(strike != 0, 'E12');
        bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

        address rdpx = getAddress('rDPX');
        uint256 currentPrice = getUsdPrice();
        // Get total premium for all calls being purchased
        uint256 premium = calculatePremium(strike, amount);

        // Total fee charged
        uint256 totalFee = calculatePurchaseFees(currentPrice, strike, amount);

        // Add to total epoch calls purchased
        totalEpochCallsPurchased[currentEpoch][strike] += amount;
        // Add to user epoch calls purchased
        userEpochCallsPurchased[currentEpoch][userStrike] += amount;
        // Add to total epoch premium
        totalEpochPremium[currentEpoch][strike] += premium; // Add to user epoch premium
        userEpochPremium[currentEpoch][userStrike] += premium;

        // Compound before updating new strike balance
        compound();

        // Add to total epoch strike balance premium to vault
        totalEpochStrikeBalance[currentEpoch][strike] += premium;
        // Add to total epoch balance premium
        totalEpochBalance[currentEpoch] += premium;

        // Transfer premium from msg.sender (need not be same as user)
        IERC20(rdpx).safeTransferFrom(
            msg.sender,
            address(this),
            premium + totalFee
        );

        if (totalFee > 0) {
            // Transfer fee to FeeDistributor
            IERC20(rdpx).safeTransfer(getAddress('FeeDistributor'), totalFee);
        }
        // Transfer doTokens to user
        IERC20(epochStrikeTokens[currentEpoch][strike]).safeTransfer(
            user,
            amount
        );

        // Stake premium into farming
        IStakingRewards(getAddress('StakingRewards')).stake(premium);

        emit NewPurchase(
            currentEpoch,
            strike,
            amount,
            premium,
            totalFee,
            user,
            msg.sender
        );

        return (premium, totalFee);
    }

    /**
     * @notice Settle calculates the PnL for the user and withdraws the PnL in rDPX to the user. Will also the burn the option tokens from the user.
     * @param strikeIndex Strike index
     * @param amount Amount of options
     * @param epoch Epoch
     * @return pnl
     */
    function settle(
        uint256 strikeIndex,
        uint256 amount,
        uint256 epoch
    ) external whenNotPaused isEligibleSender returns (uint256 pnl) {
        require(isEpochExpired[epoch], 'E17');
        require(strikeIndex < epochStrikes[epoch].length, 'E10');
        require(amount > 0, 'E11');

        uint256 strike = epochStrikes[epoch][strikeIndex];
        require(strike != 0, 'E12');
        require(
            IERC20(epochStrikeTokens[epoch][strike]).balanceOf(msg.sender) >=
                amount,
            'E16'
        );

        // Calculate PnL (in rDPX)
        pnl = calculatePnl(settlementPrices[epoch], strike, amount);

        // Total fee charged
        uint256 totalFee = calculateSettlementFees(
            settlementPrices[epoch],
            pnl,
            amount
        );

        IERC20 rdpx = IERC20(getAddress('rDPX'));

        require(pnl > 0, 'E15');

        // Burn user option tokens
        ERC20PresetMinterPauserUpgradeable(epochStrikeTokens[epoch][strike])
            .burnFrom(msg.sender, amount);

        if (totalFee > 0) {
            // Transfer fee to FeeDistributor
            rdpx.safeTransfer(getAddress('FeeDistributor'), totalFee);
        }

        // Transfer PnL to user
        rdpx.safeTransfer(msg.sender, pnl - totalFee);

        emit NewSettle(epoch, strike, msg.sender, amount, pnl);
    }

    /**
     * @notice Allows anyone to call compound()
     * @return Whether compound was successful
     */
    function compound() public whenNotPaused returns (bool) {
        require(!isEpochExpired[currentEpoch], 'E3');
        require(isVaultReady[currentEpoch], 'E20');

        IStakingRewards stakingRewards = IStakingRewards(
            getAddress('StakingRewards')
        );

        uint256 oldBalance = stakingRewards.balanceOf(address(this));

        (, uint256 rewardsRDPX) = stakingRewards.earned(address(this));

        // Account for rDPX rewards per strike deposit
        uint256[] memory strikes = epochStrikes[currentEpoch];
        for (uint256 i = 0; i < strikes.length; i++) {
            uint256 strikeRewards = (rewardsRDPX *
                totalEpochStrikeBalance[currentEpoch][strikes[i]]) /
                totalEpochBalance[currentEpoch];

            totalEpochStrikeRdpxBalance[currentEpoch][
                strikes[i]
            ] += strikeRewards;

            totalEpochStrikeBalance[currentEpoch][strikes[i]] += strikeRewards;
        }

        totalEpochBalance[currentEpoch] += rewardsRDPX;
        if (rewardsRDPX > 0) {
            // Compound staking rewards
            stakingRewards.compound();
        }

        emit Compound(
            currentEpoch,
            rewardsRDPX,
            oldBalance,
            stakingRewards.balanceOf(address(this))
        );

        return true;
    }

    /**
     * @notice Withdraws balances for a strike in a completed epoch
     * @param withdrawEpoch Epoch to withdraw from
     * @param strikeIndex Index of strike
     * @return DPX and rDPX withdrawn
     */
    function withdraw(uint256 withdrawEpoch, uint256 strikeIndex)
        external
        whenNotPaused
        isEligibleSender
        returns (uint256[2] memory)
    {
        require(isEpochExpired[withdrawEpoch], 'E17');
        require(strikeIndex < epochStrikes[withdrawEpoch].length, 'E10');

        uint256 strike = epochStrikes[withdrawEpoch][strikeIndex];
        require(strike != 0, 'E12');

        bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, strike));
        uint256 userStrikeDeposits = userEpochDeposits[withdrawEpoch][
            userStrike
        ];
        require(userStrikeDeposits > 0, 'E18');

        address rdpx = getAddress('rDPX');
        // Transfer rDPX tokens to user
        uint256 userRdpxAmount = (totalEpochStrikeRdpxBalance[withdrawEpoch][
            strike
        ] * userStrikeDeposits) /
            totalEpochStrikeDeposits[withdrawEpoch][strike];

        // Transfer DPX tokens to user
        address dpx = getAddress('DPX');
        uint256 userDpxAmount = (totalEpochStrikeDpxBalance[withdrawEpoch][
            strike
        ] * userStrikeDeposits) /
            totalEpochStrikeDeposits[withdrawEpoch][strike];

        userEpochDeposits[withdrawEpoch][userStrike] = 0;

        IERC20(rdpx).safeTransfer(msg.sender, userRdpxAmount);

        IERC20(dpx).safeTransfer(msg.sender, userDpxAmount);

        emit NewWithdraw(
            withdrawEpoch,
            strike,
            msg.sender,
            userStrikeDeposits,
            userRdpxAmount
        );

        return [userRdpxAmount, userDpxAmount];
    }

    /*==== PURE FUNCTIONS ====*/

    /// @notice Calculates the monthly expiry from a solidity date
    /// @param timestamp Timestamp from which the monthly expiry is to be calculated
    /// @return The monthly expiry
    function getMonthlyExpiryFromTimestamp(uint256 timestamp)
        public
        pure
        returns (uint256)
    {
        uint256 lastDay = BokkyPooBahsDateTimeLibrary.timestampFromDate(
            timestamp.getYear(),
            timestamp.getMonth() + 1,
            0
        );

        if (lastDay.getDayOfWeek() < 5) {
            lastDay = BokkyPooBahsDateTimeLibrary.timestampFromDate(
                lastDay.getYear(),
                lastDay.getMonth(),
                lastDay.getDay() - 7
            );
        }

        uint256 lastFridayOfMonth = BokkyPooBahsDateTimeLibrary
            .timestampFromDateTime(
                lastDay.getYear(),
                lastDay.getMonth(),
                lastDay.getDay() + 5 - lastDay.getDayOfWeek(),
                8,
                0,
                0
            );

        if (lastFridayOfMonth <= timestamp) {
            uint256 temp = BokkyPooBahsDateTimeLibrary.timestampFromDate(
                timestamp.getYear(),
                timestamp.getMonth() + 2,
                0
            );

            if (temp.getDayOfWeek() < 5) {
                temp = BokkyPooBahsDateTimeLibrary.timestampFromDate(
                    temp.getYear(),
                    temp.getMonth(),
                    temp.getDay() - 7
                );
            }

            lastFridayOfMonth = BokkyPooBahsDateTimeLibrary
                .timestampFromDateTime(
                    temp.getYear(),
                    temp.getMonth(),
                    temp.getDay() + 5 - temp.getDayOfWeek(),
                    8,
                    0,
                    0
                );
        }
        return lastFridayOfMonth;
    }

    /**
     * @notice Returns a concatenated string of a and b
     * @param a string a
     * @param b string b
     */
    function concatenate(string memory a, string memory b)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(a, b));
    }

    /// @notice Calculate Pnl
    /// @param price price of rDPX
    /// @param strike strike price of the the rDPX option
    /// @param amount amount of options
    function calculatePnl(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) public pure returns (uint256) {
        return price > strike ? (((price - strike) * amount) / price) : 0;
    }

    /*==== VIEWS ====*/

    /// @notice Calculate premium for an option
    /// @param _strike Strike price of the option
    /// @param _amount Amount of options
    function calculatePremium(uint256 _strike, uint256 _amount)
        public
        view
        returns (uint256 premium)
    {
        uint256 currentPrice = getUsdPrice();
        premium =
            (IOptionPricing(getAddress('OptionPricing')).getOptionPrice(
                false,
                getMonthlyExpiryFromTimestamp(block.timestamp),
                _strike,
                currentPrice,
                IVolatilityOracle(getAddress('VolatilityOracle')).getVolatility()
            ) * _amount) /
            currentPrice;
    }

    /// @notice Calculate Fees for purchase
    /// @param price price of DPX
    /// @param strike strike price of the the DPX option
    /// @param amount amount of options being bought
    function calculatePurchaseFees(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) public view returns (uint256) {
        return
            IFeeStrategy(getAddress('FeeStrategy')).calculatePurchaseFees(
                price,
                strike,
                amount
            );
    }

    /// @notice Calculate Fees for settlement
    /// @param settlementPrice settlement price of DPX
    /// @param pnl total pnl
    /// @param amount amount of options being settled
    function calculateSettlementFees(
        uint256 settlementPrice,
        uint256 pnl,
        uint256 amount
    ) public view returns (uint256) {
        return
            IFeeStrategy(getAddress('FeeStrategy')).calculateSettlementFees(
                settlementPrice,
                pnl,
                amount
            );
    }

    /**
     * @notice Returns start and end times for an epoch
     * @param epoch Target epoch
     */
    function getEpochTimes(uint256 epoch)
        public
        view
        epochGreaterThanZero(epoch)
        returns (uint256 start, uint256 end)
    {
        return (
            epochStartTimes[epoch],
            getMonthlyExpiryFromTimestamp(epochStartTimes[epoch])
        );
    }

    /**
     * @notice Returns epoch strikes array for an epoch
     * @param epoch Target epoch
     */
    function getEpochStrikes(uint256 epoch)
        external
        view
        epochGreaterThanZero(epoch)
        returns (uint256[] memory)
    {
        return epochStrikes[epoch];
    }

    /**
     * Returns epoch strike tokens array for an epoch
     * @param epoch Target epoch
     */
    function getEpochStrikeTokens(uint256 epoch)
        external
        view
        epochGreaterThanZero(epoch)
        returns (address[] memory)
    {
        uint256 length = epochStrikes[epoch].length;
        address[] memory _epochStrikeTokens = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            _epochStrikeTokens[i] = epochStrikeTokens[epoch][
                epochStrikes[epoch][i]
            ];
        }

        return _epochStrikeTokens;
    }

    /**
     * @notice Returns total epoch strike deposits array for an epoch
     * @param epoch Target epoch
     */
    function getTotalEpochStrikeDeposits(uint256 epoch)
        external
        view
        epochGreaterThanZero(epoch)
        returns (uint256[] memory)
    {
        uint256 length = epochStrikes[epoch].length;
        uint256[] memory _totalEpochStrikeDeposits = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            _totalEpochStrikeDeposits[i] = totalEpochStrikeDeposits[epoch][
                epochStrikes[epoch][i]
            ];
        }

        return _totalEpochStrikeDeposits;
    }

    /**
     * @notice Returns user epoch deposits array for an epoch
     * @param epoch Target epoch
     * @param user Address of the user
     */
    function getUserEpochDeposits(uint256 epoch, address user)
        external
        view
        epochGreaterThanZero(epoch)
        returns (uint256[] memory)
    {
        uint256 length = epochStrikes[epoch].length;
        uint256[] memory _userEpochDeposits = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 strike = epochStrikes[epoch][i];
            bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

            _userEpochDeposits[i] = userEpochDeposits[epoch][userStrike];
        }

        return _userEpochDeposits;
    }

    /**
     * @notice Returns total epoch calls purchased array for an epoch
     * @param epoch Target epoch
     */
    function getTotalEpochCallsPurchased(uint256 epoch)
        external
        view
        epochGreaterThanZero(epoch)
        returns (uint256[] memory)
    {
        uint256 length = epochStrikes[epoch].length;
        uint256[] memory _totalEpochCallsPurchased = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            _totalEpochCallsPurchased[i] = totalEpochCallsPurchased[epoch][
                epochStrikes[epoch][i]
            ];
        }

        return _totalEpochCallsPurchased;
    }

    /**
     * @notice Returns user epoch calls purchased array for an epoch
     * @param epoch Target epoch
     * @param user Address of the user
     */
    function getUserEpochCallsPurchased(uint256 epoch, address user)
        external
        view
        epochGreaterThanZero(epoch)
        returns (uint256[] memory)
    {
        uint256 length = epochStrikes[epoch].length;
        uint256[] memory _userEpochCallsPurchased = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 strike = epochStrikes[epoch][i];
            bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

            _userEpochCallsPurchased[i] = userEpochCallsPurchased[epoch][
                userStrike
            ];
        }

        return _userEpochCallsPurchased;
    }

    /**
     * @notice Returns total epoch premium array for an epoch
     * @param epoch Target epoch
     */
    function getTotalEpochPremium(uint256 epoch)
        external
        view
        epochGreaterThanZero(epoch)
        returns (uint256[] memory)
    {
        uint256 length = epochStrikes[epoch].length;
        uint256[] memory _totalEpochPremium = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            _totalEpochPremium[i] = totalEpochPremium[epoch][
                epochStrikes[epoch][i]
            ];
        }

        return _totalEpochPremium;
    }

    /**
     * @notice Returns user epoch premium array for an epoch
     * @param epoch Target epoch
     * @param user Address of the user
     */
    function getUserEpochPremium(uint256 epoch, address user)
        external
        view
        epochGreaterThanZero(epoch)
        returns (uint256[] memory)
    {
        uint256 length = epochStrikes[epoch].length;
        uint256[] memory _userEpochPremium = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 strike = epochStrikes[epoch][i];
            bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

            _userEpochPremium[i] = userEpochPremium[epoch][userStrike];
        }

        return _userEpochPremium;
    }

    /**
     * @notice Returns rDPX price in USD
     */
    function getUsdPrice() public view returns (uint256) {
        return IPriceOracle(getAddress('RdpxPriceOracle')).getPriceInUSD();
    }

    /**
     * @notice Gets the address of a set contract
     * @param name Name of the contract
     * @return The address of the contract
     */
    function getAddress(bytes32 name) public view returns (address) {
        return addresses[name];
    }

    /*==== MODIFIERS ====*/

    modifier onlyGovernance() {
        require(msg.sender == getAddress('Governance'), 'E22');
        _;
    }

    modifier epochGreaterThanZero(uint256 epoch) {
        require(epoch > 0, 'E13');
        _;
    }
}

// ERROR MAPPING:
// {
//   "E1": "SSOV: Address cannot be a zero address",
//   "E2": "SSOV: Input lengths must match",
//   "E3": "SSOV: Epoch must not be expired",
//   "E4": "SSOV: Cannot expire epoch before epoch's expiry",
//   "E5": "SSOV: Already bootstrapped",
//   "E6": "SSOV: Strikes have not been set for next epoch",
//   "E7": "SSOV: Previous epoch has not expired",
//   "E8": "SSOV: Deposit already started",
//   "E9": "SSOV: Cannot set next strikes before current epoch's expiry",
//   "E10": "SSOV: Invalid strike index",
//   "E11": "SSOV: Invalid amount",
//   "E12": "SSOV: Invalid strike",
//   "E13": "SSOV: Epoch passed must be greater than 0",
//   "E14": "SSOV: Option must be in exercise window",
//   "E15": "SSOV: Strike is higher than current price",
//   "E16": "SSOV: Option token balance is not enough",
//   "E17": "SSOV: Epoch must be expired",
//   "E18": "SSOV: User strike deposit amount must be greater than zero",
//   "E19": "SSOV: Deposit is only available between epochs",
//   "E20": "SSOV: Not bootstrapped",
//   "E21": "SSOV: Can not call function in exercise window",
//   "E22": "SSOV: Caller is not governance"
// }

