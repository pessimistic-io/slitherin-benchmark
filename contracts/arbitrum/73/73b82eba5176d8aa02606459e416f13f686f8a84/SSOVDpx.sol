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
import {Ownable} from "./Ownable.sol";
import {ERC20PresetMinterPauserUpgradeable} from "./ERC20PresetMinterPauserUpgradeable.sol";
import {IVolatilityOracle} from "./IVolatilityOracle.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {IStakingRewards} from "./IStakingRewards.sol";
import {IOptionPricing} from "./IOptionPricing.sol";
import {IPriceOracleAggregator} from "./IPriceOracleAggregator.sol";
import {ISSOV} from "./ISSOV.sol";

contract SSOVDpx is Ownable, ISSOV {
    using BokkyPooBahsDateTimeLibrary for uint256;
    using Strings for uint256;
    using SafeERC20 for IERC20;

    /// @dev ERC20PresetMinterPauserUpgradeable implementation address
    address public immutable erc20Implementation;

    /// @dev Boolean of whether the vault is shutdown
    bool public isVaultShutdown;

    /// @dev Current epoch for ssov
    uint256 public currentEpoch;

    /// @dev Exercise Window Size
    uint256 public windowSize = 1 hours;

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
    mapping(uint256 => mapping(uint256 => address))
        public
        override epochStrikeTokens;

    /// @notice Total epoch deposits for specific strikes
    /// @dev mapping (epoch => (strike => deposits))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochStrikeDeposits;

    /// @notice Total epoch deposits across all strikes
    /// @dev mapping (epoch => deposits)
    mapping(uint256 => uint256) public totalEpochDeposits;

    /// @notice Total epoch deposits for specific strikes
    /// @dev mapping (epoch => (strike => deposits))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochStrikeBalance;

    /// @notice Total epoch deposits across all strikes
    /// @dev mapping (epoch => deposits)
    mapping(uint256 => uint256) public totalEpochBalance;

    /// @notice Epoch deposits by user for each strike
    /// @dev mapping (epoch => (abi.encodePacked(user, strike) => user deposits))
    mapping(uint256 => mapping(bytes32 => uint256)) public userEpochDeposits;

    /// @notice Epoch DPX balance per strike after accounting for rewards
    /// @dev mapping (epoch => (strike => balance))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochStrikeDpxBalance;

    /// @notice Epoch rDPX balance per strike after accounting for rewards
    /// @dev mapping (epoch => (strike => balance))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochStrikeRdpxBalance;

    // Calls purchased for each strike in an epoch
    /// @dev mapping (epoch => (strike => calls purchased))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochCallsPurchased;

    /// @notice Calls purchased by user for each strike
    /// @dev mapping (epoch => (abi.encodePacked(user, strike) => user calls purchased))
    mapping(uint256 => mapping(bytes32 => uint256))
        public userEpochCallsPurchased;

    /// @notice Premium (and fees) collected per strike for an epoch
    /// @dev mapping (epoch => (strike => premium))
    mapping(uint256 => mapping(uint256 => uint256)) public totalEpochPremium;

    /// @notice User premium (and fees) collected per strike for an epoch
    /// @dev mapping (epoch => (abi.encodePacked(user, strike) => user premium))
    mapping(uint256 => mapping(bytes32 => uint256)) public userEpochPremium;

    /// @notice Total dpx tokens that were sent back to the buyer when a options is exercised for a certain strike
    /// @dev mapping (epoch => (strike => amount))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalTokenVaultExercises;

    bytes32 public constant PURCHASE_FEE = keccak256('purchaseFee');
    bytes32 public constant PURCHASE_FEE_CAP = keccak256('purchaseFeeCap');
    bytes32 public constant EXERCISE_FEE = keccak256('exerciseFee');
    bytes32 public constant EXERCISE_FEE_CAP = keccak256('exerciseFeeCap');
    mapping(bytes32 => uint256) public fees;

    /*==== EVENTS ====*/

    event LogAddressSet(bytes32 indexed name, address indexed destination);

    event LogNewStrike(uint256 epoch, uint256 strike);

    event LogBootstrap(uint256 epoch);

    event LogNewDeposit(uint256 epoch, uint256 strike, address user);

    event LogNewPurchase(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 amount,
        uint256 premium,
        uint256 feesToUser,
        uint256 feeToFeeDistributor
    );

    event LogNewExercise(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 amount,
        uint256 pnl,
        uint256 feeTouser,
        uint256 feeToFeeDistributor
    );

    event LogCompound(
        uint256 epoch,
        uint256 rewards,
        uint256 oldBalance,
        uint256 newBalance
    );

    event LogNewWithdrawForStrike(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 amount,
        uint256 rdpxAmount
    );

    event LogFeesUpdate(bytes32 feeKey, uint256 amount);

    event LogWindowSizeUpdate(uint256 windowSizeInHours);

    event LogVaultShutdown(bool isVaultShutdown);

    event LogEmergencySettle(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 amount, // of options
        uint256 premiumReturned
    );

    /*==== CONSTRUCTOR ====*/

    constructor(
        address _dpx,
        address _rdpx,
        address _stakingRewards,
        address _optionPricing,
        address _priceOracleAggregator,
        address _volatilityOracle,
        address _feeDistributor
    ) {
        require(_dpx != address(0), 'E1');
        require(_rdpx != address(0), 'E2');
        require(_stakingRewards != address(0), 'E3');
        require(_optionPricing != address(0), 'E4');
        require(_priceOracleAggregator != address(0), 'E5');

        addresses['FeeDistributor'] = _feeDistributor;
        addresses['DPX'] = _dpx;
        addresses['RDPX'] = _rdpx;
        addresses['StakingRewards'] = _stakingRewards;
        addresses['OptionPricing'] = _optionPricing;
        addresses['PriceOracleAggregator'] = _priceOracleAggregator;
        addresses['VolatilityOracle'] = _volatilityOracle;

        fees[PURCHASE_FEE] = 2e8 / 100; // 0.02% of the price of the base asset
        fees[PURCHASE_FEE_CAP] = 10e8; // 10% of the option price
        fees[EXERCISE_FEE] = 1e8 / 100; // 0.01% of the price of the base asset
        fees[EXERCISE_FEE_CAP] = 10e8; // 10% of the option price

        erc20Implementation = address(new ERC20PresetMinterPauserUpgradeable());

        // Max approve to stakingRewards
        IERC20(getAddress('DPX')).safeApprove(
            getAddress('StakingRewards'),
            type(uint256).max
        );
    }

    /*==== SETTER METHODS ====*/

    /// @notice Shutdown the vault
    /// @dev Can only be called by owner
    /// @return Whether it was successfully shutdown
    function shutdownVault() external onlyOwner returns (bool) {
        isVaultShutdown = true;

        _updateFinalEpochBalances(false);

        emit LogVaultShutdown(true);

        return true;
    }

    /// @notice Open the vault
    /// @dev Can only be called by owner
    /// @return Whether it was successfully opened
    function openVault() external onlyOwner returns (bool) {
        isVaultShutdown = false;

        emit LogVaultShutdown(false);

        return true;
    }

    /// @notice Update the fee percentage in the vault
    /// @dev Can only be called by owner
    /// @param feeKey The key of the fee to be updated
    /// @param feeAmount The new amount
    /// @return Whether it was successfully updated
    function updateFees(bytes32 feeKey, uint256 feeAmount)
        external
        onlyOwner
        returns (bool)
    {
        fees[feeKey] = feeAmount;

        emit LogFeesUpdate(feeKey, feeAmount);

        return true;
    }

    /// @notice Update the exercise window size of an option
    /// @dev Can only be called by owner
    /// @param _windowSize The window size
    /// @return Whether it was successfully updated
    function updateWindowSize(uint256 _windowSize)
        external
        onlyOwner
        returns (bool)
    {
        windowSize = _windowSize;
        emit LogWindowSizeUpdate(_windowSize);
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
        require(
            names.length == destinations.length,
            'Input lengths must match'
        );
        for (uint256 i = 0; i < names.length; i++) {
            bytes32 name = names[i];
            address destination = destinations[i];
            addresses[name] = destination;
            emit LogAddressSet(name, destination);
        }
        return true;
    }

    /*==== METHODS ====*/

    /// @notice Sets the current epoch as expired.
    /// @return Whether expire was successful
    function expireEpoch() external onlyOwner returns (bool) {
        // Vault must not be shutdown
        require(!isVaultShutdown, 'E24');

        // Epoch must not be expired
        require(!isEpochExpired[currentEpoch], 'E6');

        (, uint256 epochExpiry) = getEpochTimes(currentEpoch);
        // Current timestamp should be past expiry
        require((block.timestamp > epochExpiry), 'E7');

        isEpochExpired[currentEpoch] = true;

        _updateFinalEpochBalances(true);

        return true;
    }

    /// @dev Updates the final epoch DPX/rDPX balances per strike of the vault
    /// @param accountPremiums Should the fn account for premiums
    function _updateFinalEpochBalances(bool accountPremiums) internal {
        IStakingRewards stakingRewards = IStakingRewards(
            getAddress('StakingRewards')
        );

        IERC20 dpx = IERC20(getAddress('DPX'));
        IERC20 rdpx = IERC20(getAddress('RDPX'));

        if (stakingRewards.balanceOf(address(this)) > 0) {
            // Unstake all tokens from previous epoch
            stakingRewards.withdraw(stakingRewards.balanceOf(address(this)));
        }

        uint256 totalDpxRewardsClaimed = dpx.balanceOf(address(this));
        uint256 totalRdpxRewardsClaimed = rdpx.balanceOf(address(this));

        // Claim DPX and RDPX rewards
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
                uint256 dpxRewards = (totalDpxRewardsClaimed *
                    totalEpochStrikeBalance[currentEpoch][strikes[i]]) /
                    totalEpochBalance[currentEpoch];

                // Update final dpx and rdpx balances for epoch and strike
                totalEpochStrikeDpxBalance[currentEpoch][strikes[i]] +=
                    totalEpochStrikeDeposits[currentEpoch][strikes[i]] +
                    dpxRewards -
                    totalTokenVaultExercises[currentEpoch][strikes[i]];

                if (accountPremiums) {
                    totalEpochStrikeDpxBalance[currentEpoch][
                        strikes[i]
                    ] += totalEpochPremium[currentEpoch][strikes[i]];
                }

                totalEpochStrikeRdpxBalance[currentEpoch][strikes[i]] =
                    (totalRdpxRewardsClaimed *
                        totalEpochStrikeBalance[currentEpoch][strikes[i]]) /
                    totalEpochBalance[currentEpoch];
            }
        }
    }

    /**
     * @notice Bootstraps a new epoch and mints option tokens equivalent to user deposits for the epoch
     * @return Whether bootstrap was successful
     */
    function bootstrap() external onlyOwner returns (bool) {
        uint256 nextEpoch = currentEpoch + 1;

        // Vault must not be ready
        require(!isVaultReady[nextEpoch], 'E8');

        // Next epoch strike must be set
        require(epochStrikes[nextEpoch].length > 0, 'E9');

        if (currentEpoch > 0) {
            // Previous epoch must be expired
            require(isEpochExpired[currentEpoch], 'E10');
        }

        for (uint256 i = 0; i < epochStrikes[nextEpoch].length; i++) {
            uint256 strike = epochStrikes[nextEpoch][i];
            string memory name = concatenate('DPX-CALL', strike.toString());
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

        emit LogBootstrap(nextEpoch);

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
        returns (bool)
    {
        require(!isVaultShutdown, 'E24');
        uint256 nextEpoch = currentEpoch + 1;

        require(totalEpochDeposits[nextEpoch] == 0, 'E11');

        if (currentEpoch > 0) {
            (, uint256 epochExpiry) = getEpochTimes(currentEpoch);
            // Current timestamp should be past expiry
            require((block.timestamp > epochExpiry), 'E12');
        }

        // Set the next epoch strikes
        epochStrikes[nextEpoch] = strikes;
        // Set the next epoch start time
        epochStartTimes[nextEpoch] = block.timestamp;

        for (uint256 i = 0; i < strikes.length; i++)
            emit LogNewStrike(nextEpoch, strikes[i]);
        return true;
    }

    /**
     * @notice Deposits dpx into the ssov to mint options in the next epoch for selected strikes
     * @param strikeIndex Index of strike
     * @param amount Amout of DPX to deposit
     * @return Whether deposit was successful
     */
    function deposit(uint256 strikeIndex, uint256 amount)
        public
        returns (bool)
    {
        require(!isVaultShutdown, 'E24');

        uint256 nextEpoch = currentEpoch + 1;

        if (currentEpoch > 0) {
            require(
                isEpochExpired[currentEpoch] && !isVaultReady[nextEpoch],
                'E26'
            );
        }

        // Must be a valid strikeIndex
        require(strikeIndex < epochStrikes[nextEpoch].length, 'E13');

        // Must +ve amount
        require(amount > 0, 'E14');

        // Must be a valid strike
        uint256 strike = epochStrikes[nextEpoch][strikeIndex];
        require(strike != 0, 'E15');

        bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, strike));

        // Transfer DPX from user to ssov
        IERC20(getAddress('DPX')).safeTransferFrom(
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

        emit LogNewDeposit(nextEpoch, strike, msg.sender);

        return true;
    }

    /**
     * @notice Deposit DPX multiple times
     * @param strikeIndices Indices of strikes to deposit into
     * @param amounts Amount of DPX to deposit into each strike index
     * @return Whether deposits went through successfully
     */
    function depositMultiple(
        uint256[] memory strikeIndices,
        uint256[] memory amounts
    ) public returns (bool) {
        require(strikeIndices.length == amounts.length, 'E16');

        for (uint256 i = 0; i < strikeIndices.length; i++)
            deposit(strikeIndices[i], amounts[i]);
        return true;
    }

    /**
     * @notice Purchases calls for the current epoch
     * @param strikeIndex Strike index for current epoch
     * @param amount Amount of calls to purchase
     * @return Whether purchase was successful
     */
    function purchase(uint256 strikeIndex, uint256 amount)
        external
        override
        returns (uint256, uint256)
    {
        require(!isVaultShutdown, 'E24');
        require(currentEpoch > 0, 'E17');

        // Must be a valid strikeIndex
        require(strikeIndex < epochStrikes[currentEpoch].length, 'E13');

        // Must positive amount
        require(amount > 0, 'E14');

        // Must be a valid strike
        uint256 strike = epochStrikes[currentEpoch][strikeIndex];
        require(strike != 0, 'E15');
        bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, strike));

        address dpx = getAddress('DPX');
        uint256 currentPrice = getUsdPrice(dpx);
        // Get total premium for all calls being purchased
        uint256 premium = (IOptionPricing(getAddress('OptionPricing'))
            .getOptionPrice(
                false,
                getMonthlyExpiryFromTimestamp(block.timestamp),
                strike,
                currentPrice,
                IVolatilityOracle(getAddress('VolatilityOracle')).getVolatility()
            ) * amount) / currentPrice;

        // total fees charged
        uint256 totalFees = calculateFees(premium, currentPrice, true);

        // 30% ( number * 0.3 ) of fees for FeeDistributor
        uint256 feetoFeeDistrubutor = (totalFees * 3) / 10;

        // Add to total epoch calls purchased
        totalEpochCallsPurchased[currentEpoch][strike] += amount;
        // Add to user epoch calls purchased
        userEpochCallsPurchased[currentEpoch][userStrike] += amount;
        // Add to total epoch premium + fees
        totalEpochPremium[currentEpoch][strike] +=
            premium +
            (totalFees - feetoFeeDistrubutor);
        // Add to user epoch premium + fees
        userEpochPremium[currentEpoch][userStrike] +=
            premium +
            (totalFees - feetoFeeDistrubutor);

        // Compound before updating new strike balance
        compound();

        // Add to total epoch strike balance premium + fee to vault
        totalEpochStrikeBalance[currentEpoch][strike] +=
            premium +
            (totalFees - feetoFeeDistrubutor);

        // Add to total epoch balance premium + fee
        totalEpochBalance[currentEpoch] +=
            premium +
            (totalFees - feetoFeeDistrubutor);

        // Transfer usd equivalent to premium from user
        IERC20(dpx).safeTransferFrom(
            msg.sender,
            address(this),
            premium + totalFees
        );

        IERC20(dpx).safeTransfer(
            getAddress('FeeDistributor'),
            feetoFeeDistrubutor
        );

        // Transfer doTokens to user
        IERC20(epochStrikeTokens[currentEpoch][strike]).safeTransfer(
            msg.sender,
            amount
        );

        // Stake premium into farming
        IStakingRewards(getAddress('StakingRewards')).stake(
            premium + (totalFees - feetoFeeDistrubutor)
        );

        emit LogNewPurchase(
            currentEpoch,
            strike,
            msg.sender,
            amount,
            premium,
            totalFees,
            feetoFeeDistrubutor
        );

        return (premium, totalFees);
    }

    /**
     * @notice Exercise calculates the PnL for the user. Withdraw the PnL in DPX from the SSF and transfer it to the user. Will also the burn the doTokens from the user.
     * @param strikeIndex Strike index for current epoch
     * @param amount Amount of calls to exercise
     * @param user Address of the user
     * @return Pnl and Fee
     */
    function exercise(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) external override returns (uint256, uint256) {
        require(!isVaultShutdown, 'E24');

        uint256 epoch = currentEpoch;

        (, uint256 expiry) = getEpochTimes(epoch);

        // Must be in exercise window
        require(isExerciseWindow(expiry), 'E18');

        // Must be a valid strikeIndex
        require(strikeIndex < epochStrikes[epoch].length, 'E13');

        // Must positive amount
        require(amount > 0, 'E14');

        // Must be a valid strike
        uint256 strike = epochStrikes[epoch][strikeIndex];
        require(strike != 0, 'E15');

        uint256 currentPrice = getUsdPrice(getAddress('DPX'));

        // Revert if strike price is higher than current price
        require(strike < currentPrice, 'E19');

        // Revert if user is zero address
        require(user != address(0), 'E20');

        // Revert if user does not have enough option token balance for the amount specified
        require(
            IERC20(epochStrikeTokens[epoch][strike]).balanceOf(user) >= amount,
            'E21'
        );

        // Calculate PnL (in DPX)
        uint256 PnL = (((currentPrice - strike) * amount) / currentPrice);

        // fee to deduct from users PnL
        uint256 feeToUser = calculateFees(PnL, currentPrice, false);

        // 30% fees to fee distributor
        uint256 feeToFeeDistributor = (feeToUser * 3) / 10;

        // Burn user option tokens
        ERC20PresetMinterPauserUpgradeable(epochStrikeTokens[epoch][strike])
            .burnFrom(user, amount);

        // Update state to account for exercised options (amount of DPX used in exercising)
        totalTokenVaultExercises[epoch][strike] += PnL;

        if (!isVaultShutdown) {
            IStakingRewards(getAddress('StakingRewards')).withdraw(PnL);
        }

        // Transfer PnL to user
        IERC20(getAddress('DPX')).safeTransfer(user, PnL - feeToUser);

        // transfer fees to FeeDistributor
        IERC20(getAddress('DPX')).safeTransfer(
            getAddress('FeeDistributor'),
            feeToFeeDistributor
        );

        emit LogNewExercise(
            epoch,
            strike,
            user,
            amount,
            PnL,
            feeToUser,
            feeToFeeDistributor
        );

        return (PnL, feeToUser);
    }

    /**
     * @notice Allows a user to settle their options due to an emergency shutdown. Returns the premium to the user.
     * @param strikeIndex Strike index for current epoch
     * @param amount Amount of calls to exercise
     * @param user Address of the user
     */
    function emergencySettle(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) external returns (uint256) {
        // Vault must be shutdown
        require(isVaultShutdown, 'E25');

        uint256 epoch = currentEpoch;

        // Must be a valid strikeIndex
        require(strikeIndex < epochStrikes[epoch].length, 'E13');

        // Must positive amount
        require(amount > 0, 'E14');

        // Must be a valid strike
        uint256 strike = epochStrikes[epoch][strikeIndex];
        require(strike != 0, 'E15');

        // Revert if user is zero address
        require(user != address(0), 'E20');

        // Revert if user does not have enough option token balance for the amount specified
        require(
            IERC20(epochStrikeTokens[epoch][strike]).balanceOf(user) >= amount,
            'E21'
        );

        // Burn user option tokens
        ERC20PresetMinterPauserUpgradeable(epochStrikeTokens[epoch][strike])
            .burnFrom(user, amount);

        bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, strike));

        uint256 userPremium = userEpochPremium[epoch][userStrike];

        userEpochPremium[epoch][userStrike] = 0;

        // Transfer premium to user
        IERC20(getAddress('DPX')).safeTransfer(user, userPremium);

        emit LogEmergencySettle(epoch, strike, user, amount, userPremium);

        return userPremium;
    }

    /**
     * @notice Allows anyone to call compound()
     * @return Whether compound was successful
     */
    function compound() public returns (bool) {
        require(!isVaultShutdown, 'E24');
        require(!isEpochExpired[currentEpoch], 'E6');
        require(isVaultReady[currentEpoch], 'E27');

        if (currentEpoch == 0) {
            return false;
        }

        IStakingRewards stakingRewards = IStakingRewards(
            getAddress('StakingRewards')
        );

        uint256 oldBalance = stakingRewards.balanceOf(address(this));

        (uint256 rewardsDPX, ) = stakingRewards.earned(address(this));

        // Account for DPX rewards per strike deposit
        uint256[] memory strikes = epochStrikes[currentEpoch];
        for (uint256 i = 0; i < strikes.length; i++) {
            uint256 strikeRewards = (rewardsDPX *
                totalEpochStrikeDeposits[currentEpoch][strikes[i]]) /
                totalEpochDeposits[currentEpoch];

            totalEpochStrikeDpxBalance[currentEpoch][
                strikes[i]
            ] += strikeRewards;

            totalEpochStrikeBalance[currentEpoch][strikes[i]] += strikeRewards;
        }

        totalEpochBalance[currentEpoch] += rewardsDPX;
        if (rewardsDPX > 0) {
            // Compound staking rewards
            stakingRewards.compound();
        }

        emit LogCompound(
            currentEpoch,
            rewardsDPX,
            oldBalance,
            stakingRewards.balanceOf(address(this))
        );

        return true;
    }

    /**
     * @notice Withdraws balances for a strike in a completed epoch
     * @param withdrawEpoch Epoch to withdraw from
     * @param strikeIndex Index of strike
     * @return Whether withdraw was successful
     */
    function withdrawForStrike(uint256 withdrawEpoch, uint256 strikeIndex)
        external
        returns (bool)
    {
        // Epoch must be expired
        require(isEpochExpired[withdrawEpoch], 'E22');

        _withdraw(withdrawEpoch, strikeIndex);

        return true;
    }

    /**
     * @notice Emergency withdraws balances for a strike
     * @dev Vault must be shutdown for this
     * @param strikeIndex Index of strike
     * @return Whether withdraw was successful
     */
    function emergencyWithdrawForStrike(uint256 strikeIndex)
        external
        returns (bool)
    {
        require(isVaultShutdown, 'E25');

        _withdraw(currentEpoch, strikeIndex);

        return true;
    }

    /// @dev Internal function to handle a withdraw
    /// @param withdrawEpoch Epoch to withdraw from
    /// @param strikeIndex Index of strike
    function _withdraw(uint256 withdrawEpoch, uint256 strikeIndex) internal {
        // Must be a valid strikeIndex
        require(strikeIndex < epochStrikes[withdrawEpoch].length, 'E13');

        // Must be a valid strike
        uint256 strike = epochStrikes[withdrawEpoch][strikeIndex];
        require(strike != 0, 'E15');

        // Must be a valid user strike deposit amount
        bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, strike));
        uint256 userStrikeDeposits = userEpochDeposits[withdrawEpoch][
            userStrike
        ];

        require(userStrikeDeposits > 0, 'E23');

        address rdpx = getAddress('RDPX');
        // Transfer RDPX tokens to user
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

        emit LogNewWithdrawForStrike(
            withdrawEpoch,
            strike,
            msg.sender,
            userStrikeDeposits,
            userRdpxAmount
        );
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
                12,
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
                    12,
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

    /*==== VIEWS ====*/

    /// @notice calculates fees for a given amount
    /// @param amountToCharge amount from which fees is charged from
    /// @param dpxPrice last price of DPX in USDT
    /// @param isPurchase if true, uses purchase fees values, if false, uses exercise fees values
    function calculateFees(
        uint256 amountToCharge,
        uint256 dpxPrice,
        bool isPurchase
    ) public view returns (uint256) {
        uint256 fee = isPurchase ? fees[PURCHASE_FEE] : fees[EXERCISE_FEE];
        uint256 feeCap = isPurchase
            ? fees[PURCHASE_FEE_CAP]
            : fees[EXERCISE_FEE_CAP];

        uint256 baseAssetFees = (dpxPrice * fee) / 1e10;
        uint256 optionPriceFees = (amountToCharge * feeCap * dpxPrice) / 1e28;

        if (baseAssetFees > optionPriceFees) {
            return (optionPriceFees * 1e18) / dpxPrice;
        } else {
            return (baseAssetFees * 1e18) / dpxPrice;
        }
    }

    /**
     * @notice Returns start and end times for an epoch
     * @param epoch Target epoch
     */
    function getEpochTimes(uint256 epoch)
        public
        view
        returns (uint256 start, uint256 end)
    {
        require(epoch > 0, 'E17');

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
        returns (uint256[] memory)
    {
        require(epoch > 0, 'E17');

        return epochStrikes[epoch];
    }

    /**
     * Returns epoch strike tokens array for an epoch
     * @param epoch Target epoch
     */
    function getEpochStrikeTokens(uint256 epoch)
        external
        view
        returns (address[] memory)
    {
        require(epoch > 0, 'E17');

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
        returns (uint256[] memory)
    {
        require(epoch > 0, 'E17');

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
        returns (uint256[] memory)
    {
        require(epoch > 0, 'E17');

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
        returns (uint256[] memory)
    {
        require(epoch > 0, 'E17');

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
        returns (uint256[] memory)
    {
        require(epoch > 0, 'E17');

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
        returns (uint256[] memory)
    {
        require(epoch > 0, 'E17');

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
        returns (uint256[] memory)
    {
        require(epoch > 0, 'E17');

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
     * @notice Update & Returns token's price in USD
     * @param _token Address of the token
     */
    function getUsdPrice(address _token) public returns (uint256) {
        return
            IPriceOracleAggregator(getAddress('PriceOracleAggregator'))
                .getPriceInUSD(_token);
    }

    /**
     * @notice Returns token's price in USD
     * @param _token Address of the token
     */
    function viewUsdPrice(address _token) external view returns (uint256) {
        return
            IPriceOracleAggregator(getAddress('PriceOracleAggregator'))
                .viewPriceInUSD(_token);
    }

    /**
     * @notice Returns true if exercise can be called
     * @param expiry The expiry of the option
     */
    function isExerciseWindow(uint256 expiry) public view returns (bool) {
        return ((block.timestamp >= expiry - windowSize) &&
            (block.timestamp < expiry));
    }

    /**
     * @notice Gets the address of a set contract
     * @param name Name of the contract
     * @return The address of the contract
     */
    function getAddress(bytes32 name) public view override returns (address) {
        return addresses[name];
    }
}

