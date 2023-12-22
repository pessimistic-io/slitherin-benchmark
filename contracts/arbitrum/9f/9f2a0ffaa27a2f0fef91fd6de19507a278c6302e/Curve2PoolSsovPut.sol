//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import {Clones} from "./Clones.sol";
import {BokkyPooBahsDateTimeLibrary} from "./BokkyPooBahsDateTimeLibrary.sol";
import {SafeERC20} from "./SafeERC20.sol";

// Contracts
import {Pausable} from "./Pausable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ContractWhitelist} from "./ContractWhitelist.sol";
import {OptionsToken} from "./OptionsToken.sol";

// Interfaces
import {IERC20} from "./IERC20.sol";
import {IOptionPricing} from "./IOptionPricing.sol";
import {IFeeStrategy} from "./IFeeStrategy.sol";

interface IPriceOracle {
    function latestAnswer() external view returns (int256);
}

interface IVolatilityOracle {
    function getVolatility(uint256) external view returns (uint256);
}

interface ICrv2Pool is IERC20 {
    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount)
        external
        returns (uint256);

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external returns (uint256);

    function get_virtual_price() external view returns (uint256);

    function coins(uint256) external view returns (address);
}

interface ICrv2PoolGauge {
    function deposit(
        uint256 _value,
        address _addr,
        bool _claim_rewards
    ) external;

    function withdraw(uint256 _value, bool _claim_rewards) external;

    function claim_rewards() external;
}

/*                                                                               
                                                       ▓                        
                       ▓                                 ▓                      
                     ▓▓                                   ▓▓                    
                   ▓▓                                      ▓▓▓                  
                 ▓▓▓                                         ▓▓▓                
               ▓▓▓▓                                           ▓▓▓▓              
             ▓▓▓▓▓                                             ▓▓▓▓▓            
           ▓▓▓▓▓                                                ▓▓▓▓▓▓          
         ▓▓▓▓▓▓                                                   ▓▓▓▓▓▓        
       ▓▓▓▓▓▓▓                                                     ▓▓▓▓▓▓▓      
     ▓▓▓▓▓▓▓                                                        ▓▓▓▓▓▓▓▓    
   ▓▓▓▓▓▓▓▓                                                          ▓▓▓▓▓▓▓▓   
 ▓▓▓▓▓▓▓▓▓                                                             ▓▓▓▓▓▓▓▓ 
▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                                                   ▓▓▓▓▓▓▓▓▓▓▓▓▓
 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                                      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 
      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                                 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓     
              ▓▓▓▓▓▓▓▓▓▓▓                               ▓▓▓▓▓▓▓▓▓▓▓▓▓           
                ▓▓▓▓▓▓▓▓                               ▓▓▓▓▓▓▓▓                 
               ▓▓▓▓▓▓▓                                 ▓▓▓▓▓▓                   
              ▓▓▓▓▓▓▓                                 ▓▓▓▓▓▓▓                   
             ▓▓▓▓▓▓▓         ▓                        ▓▓▓▓▓▓▓                   
            ▓▓▓▓▓▓▓          ▓▓▓                      ▓▓▓▓▓▓▓                   
            ▓▓▓▓▓▓          ▓▓▓▓▓▓                     ▓▓▓▓▓▓                   
           ▓▓▓▓▓▓▓          ▓▓▓▓▓▓▓▓                   ▓▓▓▓▓▓▓                  
           ▓▓▓▓▓▓▓           ▓▓▓▓▓▓▓▓                   ▓▓▓▓▓▓▓                 
            ▓▓▓▓▓▓▓             ▓▓▓▓▓▓                   ▓▓▓▓▓▓▓                
            ▓▓▓▓▓▓▓▓▓                                     ▓▓▓▓▓▓▓               
              ▓▓▓▓▓▓▓▓▓▓                                   ▓▓▓▓▓▓▓              
               ▓▓▓▓▓▓▓▓▓▓▓▓▓                                ▓▓▓▓▓▓▓             
                  ▓▓▓▓▓▓▓▓▓▓▓▓                               ▓▓▓▓▓▓▓            
                      ▓▓▓▓▓▓▓▓▓▓                              ▓▓▓▓▓▓            
                         ▓▓▓▓▓▓▓▓                             ▓▓▓▓▓▓▓           
                           ▓▓▓▓▓▓▓▓                            ▓▓▓▓▓▓           
                            ▓▓▓▓▓▓▓▓                           ▓▓▓▓▓▓▓          
                              ▓▓▓▓▓▓▓▓                         ▓▓▓▓▓▓           
                               ▓▓▓▓▓▓▓▓▓                     ▓▓▓▓▓▓▓▓           
                                 ▓▓▓▓▓▓▓▓▓                 ▓▓▓▓▓▓▓▓▓            
                                   ▓▓▓▓▓▓▓▓▓▓           ▓▓▓▓▓▓▓▓▓▓              
                                     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓               
                                       ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                  
                                           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
*/

/// @title Curve 2Pool (USDC/USDT) SSOV Puts
/// @dev Option tokens are in erc20 18 decimals
/// Base token and quote token calculations are done in their respective erc20 precision
/// Strikes are in 1e8 precision
/// Price is in 1e8 precision
contract Curve2PoolSsovPut is ContractWhitelist, Pausable, ReentrancyGuard {
    using BokkyPooBahsDateTimeLibrary for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for ICrv2Pool;

    /// @dev OptionsToken implementation address
    address public immutable optionsTokenImplementation;

    /// @dev QuoteToken (Curve 2Pool LP token)
    ICrv2Pool public immutable quoteToken;

    /// @dev BaseToken symbol
    string public baseTokenSymbol;

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

    /// @notice Epoch deposits by user for each strike
    /// @dev mapping (epoch => (abi.encodePacked(user, strike) => user deposits))
    mapping(uint256 => mapping(bytes32 => uint256)) public userEpochDeposits;

    /// @notice Total epoch deposits for specific strikes
    /// @dev mapping (epoch => (strike => deposits))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochStrikeDeposits;

    /// @notice Total epoch deposits across all strikes
    /// @dev mapping (epoch => deposits)
    mapping(uint256 => uint256) public totalEpochDeposits;

    /// @notice Epoch balance after unstaking
    /// @dev mapping (epoch => balance)
    mapping(uint256 => uint256) public epochBalanceAfterUnstaking;

    /// @notice Final QuoteTokens withdrawable at the end of the epoch per strike
    /// @dev mapping (epoch => (strike => quote token balance))
    mapping(uint256 => mapping(uint256 => uint256))
        public finalQuoteTokenBalancePerStrike;

    /// @notice Final crv amounts for each epoch after unstaking
    /// @dev mapping (epoch => crv to distribute)
    mapping(uint256 => uint256) public crvToDistribute;

    // Puts purchased for each strike in an epoch
    /// @dev mapping (epoch => (strike => puts purchased))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochPutsPurchased;

    /// @notice Puts purchased by user for each strike
    /// @dev mapping (epoch => (abi.encodePacked(user, strike) => user puts purchased))
    mapping(uint256 => mapping(bytes32 => uint256))
        public userEpochPutsPurchased;

    /// @notice Premium collected per strike for an epoch
    /// @dev mapping (epoch => (strike => premium))
    mapping(uint256 => mapping(uint256 => uint256))
        public totalEpochStrikePremium;

    /// @notice Total premium collected for an epoch
    /// @dev mapping (epoch => premium)
    mapping(uint256 => uint256) public totalEpochPremium;

    /// @notice User premium collected per strike for an epoch
    /// @dev mapping (epoch => (abi.encodePacked(user, strike) => user premium))
    mapping(uint256 => mapping(bytes32 => uint256)) public userEpochPremium;

    /// @dev epoch => settlement price
    mapping(uint256 => uint256) public settlementPrices;

    /*==== ERRORS & EVENTS ====*/

    event ExpireDelayToleranceUpdate(uint256 expireDelayTolerance);

    event WindowSizeUpdate(uint256 windowSizeInHours);

    event AddressSet(bytes32 indexed name, address indexed destination);

    event EmergencyWithdraw(address sender);

    event EpochExpired(address sender, uint256 settlementPrice);

    event StrikeSet(uint256 epoch, uint256 strike);

    event Bootstrap(uint256 epoch);

    event Deposit(
        uint256 epoch,
        uint256 strike,
        uint256 amount,
        address user,
        address sender
    );

    event Purchase(
        uint256 epoch,
        uint256 strike,
        uint256 amount,
        uint256 premium,
        uint256 fee,
        address user,
        address sender
    );

    event Settle(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 amount,
        uint256 pnl, // pnl transfered to the user
        uint256 fee // fee sent to fee distributor
    );

    event Compound(
        uint256 epoch,
        uint256 rewards,
        uint256 oldBalance,
        uint256 newBalance
    );

    event Withdraw(
        uint256 epoch,
        uint256 strike,
        address user,
        uint256 userDeposits,
        uint256 quoteTokenWithdrawn,
        uint256 crvRewards
    );

    error ZeroAddress(bytes32 source, address destination);

    /*==== CONSTRUCTOR ====*/

    constructor(
        bytes32[] memory sources,
        address[] memory destinations,
        string memory _baseTokenSymbol,
        address _quoteToken
    ) {
        require(_quoteToken != address(0), 'E1');

        require(sources.length == destinations.length, 'E26');

        for (uint256 i = 0; i < destinations.length; i++) {
            if (destinations[i] == address(0)) {
                revert ZeroAddress(sources[i], destinations[i]);
            }
            addresses[sources[i]] = destinations[i];
        }

        addresses['Governance'] = msg.sender;

        quoteToken = ICrv2Pool(_quoteToken);
        baseTokenSymbol = _baseTokenSymbol;

        optionsTokenImplementation = address(new OptionsToken());

        quoteToken.safeIncreaseAllowance(
            getAddress('Curve2PoolGauge'),
            type(uint256).max
        );
    }

    /*==== SETTER METHODS ====*/

    /// @notice Pauses the vault for emergency cases
    /// @dev Can only be called by governance
    /// @return Whether it was successfully paused
    function pause() external onlyGovernance returns (bool) {
        _pause();
        _updateFinalEpochBalances();
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
    /// @param tokens The list of erc20 tokens to withdraw
    /// @param transferNative Whether should transfer the native currency
    /// @return Whether emergency withdraw was successful
    function emergencyWithdraw(address[] calldata tokens, bool transferNative)
        external
        onlyGovernance
        whenPaused
        returns (bool)
    {
        if (transferNative) payable(msg.sender).transfer(address(this).balance);

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            token.safeTransfer(msg.sender, token.balanceOf(address(this)));
        }

        emit EmergencyWithdraw(msg.sender);

        return true;
    }

    /// @notice Sets the current epoch as expired.
    /// @return Whether expire was successful
    function expireEpoch()
        external
        whenNotPaused
        isEligibleSender
        nonReentrant
        returns (bool)
    {
        require(!isEpochExpired[currentEpoch], 'E3');
        (, uint256 epochExpiry) = getEpochTimes(currentEpoch);
        require((block.timestamp >= epochExpiry), 'E4');
        require(block.timestamp <= epochExpiry + expireDelayTolerance, 'E21');

        settlementPrices[currentEpoch] = getUsdPrice();

        _updateFinalEpochBalances();

        isEpochExpired[currentEpoch] = true;

        emit EpochExpired(msg.sender, settlementPrices[currentEpoch]);

        return true;
    }

    /// @notice Sets the current epoch as expired. Only can be called by governance.
    /// @param settlementPrice The settlement price
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

        _updateFinalEpochBalances();

        isEpochExpired[currentEpoch] = true;

        emit EpochExpired(msg.sender, settlementPrices[currentEpoch]);

        return true;
    }

    /// @dev Updates the final epoch QuoteToken balances per strike of the vault
    function _updateFinalEpochBalances() private {
        IERC20 crv = IERC20(getAddress('CRV'));

        uint256 crvRewards = crv.balanceOf(address(this));

        // Withdraw curve LP from the curve gauge and claim rewards
        ICrv2PoolGauge(getAddress('Curve2PoolGauge')).withdraw(
            totalEpochDeposits[currentEpoch] + totalEpochPremium[currentEpoch],
            true /* _claim_rewards */
        );

        crvRewards = crv.balanceOf(address(this)) - crvRewards;

        crvToDistribute[currentEpoch] = crvRewards;

        if (totalEpochDeposits[currentEpoch] > 0) {
            uint256[] memory strikes = epochStrikes[currentEpoch];

            for (uint256 i = 0; i < strikes.length; i++) {
                uint256 strikeBalanceWithoutSettlement = totalEpochStrikeDeposits[
                        currentEpoch
                    ][strikes[i]] +
                        totalEpochStrikePremium[currentEpoch][strikes[i]];

                // PnL from ssov option settlements
                uint256 settlement = calculatePnl(
                    settlementPrices[currentEpoch],
                    strikes[i],
                    totalEpochPutsPurchased[currentEpoch][strikes[i]]
                );

                finalQuoteTokenBalancePerStrike[currentEpoch][strikes[i]] =
                    strikeBalanceWithoutSettlement -
                    settlement;
            }
        }
    }

    /**
     * @notice Bootstraps a new epoch and mints option tokens equivalent to user deposits for the epoch
     * @return Whether bootstrap was successful
     */
    function bootstrap()
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        returns (bool)
    {
        uint256 nextEpoch = currentEpoch + 1;
        require(!isVaultReady[nextEpoch], 'E5');
        require(epochStrikes[nextEpoch].length > 0, 'E6');

        if (currentEpoch > 0) {
            // Previous epoch must be expired
            require(isEpochExpired[currentEpoch], 'E7');
        }

        for (uint256 i = 0; i < epochStrikes[nextEpoch].length; i++) {
            uint256 strike = epochStrikes[nextEpoch][i];
            // Create options tokens representing puts for selected strike in epoch
            OptionsToken _optionsToken = OptionsToken(
                Clones.clone(optionsTokenImplementation)
            );
            (, uint256 expiry) = getEpochTimes(nextEpoch);
            _optionsToken.initialize(
                address(this),
                address(quoteToken),
                true,
                strike,
                expiry,
                nextEpoch,
                baseTokenSymbol
            );
            epochStrikeTokens[nextEpoch][strike] = address(_optionsToken);
            // Mint tokens equivalent to deposits for strike in epoch
            _optionsToken.mint(
                address(this),
                (totalEpochStrikeDeposits[nextEpoch][strike] * getLpPrice()) /
                    (strike * 1e10)
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
            emit StrikeSet(nextEpoch, strikes[i]);
        return true;
    }

    /**
     * @notice Deposit Curve 2Pool LP into the ssov to mint options in the next epoch for selected strikes
     * @param strikeIndex Index of strike
     * @param amount Amout of QuoteToken to deposit
     * @param user Address of the user to deposit for
     * @return Whether deposit was successful
     */
    function deposit(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) public whenNotPaused isEligibleSender nonReentrant returns (bool) {
        uint256 nextEpoch = currentEpoch + 1;

        if (currentEpoch > 0) {
            require(
                isEpochExpired[currentEpoch] && !isVaultReady[nextEpoch],
                'E18'
            );
        }

        // Must be a valid strikeIndex
        require(strikeIndex < epochStrikes[nextEpoch].length, 'E10');

        // Must +ve amount
        require(amount > 0, 'E11');

        // Must be a valid strike
        uint256 strike = epochStrikes[nextEpoch][strikeIndex];
        require(strike != 0, 'E12');

        bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

        // Transfer QuoteToken from msg.sender (maybe different from user param) to ssov
        quoteToken.safeTransferFrom(msg.sender, address(this), amount);

        // Add to user epoch deposits
        userEpochDeposits[nextEpoch][userStrike] += amount;
        // Add to total epoch strike deposits
        totalEpochStrikeDeposits[nextEpoch][strike] += amount;
        // Add to total epoch deposits
        totalEpochDeposits[nextEpoch] += amount;

        // Deposit curve LP to the curve gauge for rewards
        ICrv2PoolGauge(getAddress('Curve2PoolGauge')).deposit(
            amount,
            address(this),
            false /* _claim_rewards */
        );

        emit Deposit(nextEpoch, strike, amount, user, msg.sender);

        return true;
    }

    /**
     * @notice Deposit QuoteToken into multiple strikes
     * @param strikeIndices Indices of strikes to deposit into
     * @param amounts Amount of QutoeToken to deposit into each strike index
     * @param user Address of the user to deposit for
     * @return Whether deposits went through successfully
     */
    function depositMultiple(
        uint256[] memory strikeIndices,
        uint256[] memory amounts,
        address user
    ) external returns (bool) {
        require(strikeIndices.length == amounts.length, 'E2');

        for (uint256 i = 0; i < strikeIndices.length; i++)
            deposit(strikeIndices[i], amounts[i], user);
        return true;
    }

    /**
     * @notice Purchases puts for the current epoch
     * @param strikeIndex Strike index for current epoch
     * @param amount Amount of puts to purchase
     * @param user User to purchase options for
     * @return Whether purchase was successful
     */
    function purchase(
        uint256 strikeIndex,
        uint256 amount,
        address user
    )
        external
        whenNotPaused
        isEligibleSender
        nonReentrant
        returns (uint256, uint256)
    {
        (, uint256 epochExpiry) = getEpochTimes(currentEpoch);
        require((block.timestamp < epochExpiry), 'E3');
        require(isVaultReady[currentEpoch], 'E19');
        require(strikeIndex < epochStrikes[currentEpoch].length, 'E10');
        require(amount > 0, 'E11');

        uint256 strike = epochStrikes[currentEpoch][strikeIndex];
        require(strike != 0, 'E12');
        bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

        uint256 currentPrice = getUsdPrice();

        // Get total premium for all puts being purchased
        uint256 premium = calculatePremium(strike, amount);

        // Total fee charged
        uint256 totalFee = calculatePurchaseFees(currentPrice, strike, amount);

        // Add to total epoch puts purchased
        totalEpochPutsPurchased[currentEpoch][strike] += amount;
        // Add to user epoch puts purchased
        userEpochPutsPurchased[currentEpoch][userStrike] += amount;
        // Add to epoch premium per strike
        totalEpochStrikePremium[currentEpoch][strike] += premium;
        // Add to total epoch premium
        totalEpochPremium[currentEpoch] += premium;
        // Add to user epoch premium
        userEpochPremium[currentEpoch][userStrike] += premium;

        // Transfer premium from msg.sender (need not be same as user)
        quoteToken.safeTransferFrom(
            msg.sender,
            address(this),
            premium + totalFee
        );

        if (totalFee > 0) {
            // Transfer fee to FeeDistributor
            quoteToken.safeTransfer(getAddress('FeeDistributor'), totalFee);
        }

        // Transfer option tokens to user
        IERC20(epochStrikeTokens[currentEpoch][strike]).safeTransfer(
            user,
            amount
        );

        // Deposit curve LP to the curve gauge for rewards
        ICrv2PoolGauge(getAddress('Curve2PoolGauge')).deposit(
            premium,
            address(this),
            false /* _claim_rewards */
        );

        emit Purchase(
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
     * @notice Settle calculates the PnL for the user and withdraws the PnL in the BaseToken to the user. Will also the burn the option tokens from the user.
     * @param strikeIndex Strike index
     * @param amount Amount of options
     * @return pnl
     */
    function settle(
        uint256 strikeIndex,
        uint256 amount,
        uint256 epoch
    )
        external
        whenNotPaused
        isEligibleSender
        nonReentrant
        returns (uint256 pnl)
    {
        require(isEpochExpired[epoch], 'E16');
        require(strikeIndex < epochStrikes[epoch].length, 'E10');
        require(amount > 0, 'E11');

        uint256 strike = epochStrikes[epoch][strikeIndex];
        require(strike != 0, 'E12');
        require(
            IERC20(epochStrikeTokens[epoch][strike]).balanceOf(msg.sender) >=
                amount,
            'E15'
        );

        // Calculate pnl
        pnl = calculatePnl(settlementPrices[epoch], strike, amount);

        // Total fee charged
        uint256 totalFee = calculateSettlementFees(
            settlementPrices[epoch],
            pnl,
            amount
        );

        require(pnl > 0, 'E14');

        // Burn user option tokens
        OptionsToken(epochStrikeTokens[epoch][strike]).burnFrom(
            msg.sender,
            amount
        );

        if (totalFee > 0) {
            // Transfer fee to FeeDistributor
            quoteToken.safeTransfer(getAddress('FeeDistributor'), totalFee);
        }

        // Transfer PnL to user
        quoteToken.safeTransfer(msg.sender, pnl - totalFee);

        emit Settle(
            epoch,
            strike,
            msg.sender,
            amount,
            pnl - totalFee,
            totalFee
        );
    }

    function _withdraw(uint256 epoch, uint256 strikeIndex)
        private
        whenNotPaused
        isEligibleSender
        nonReentrant
        returns (uint256 userQuoteTokenWithdrawAmount, uint256 rewards)
    {
        require(isEpochExpired[epoch], 'E16');
        require(strikeIndex < epochStrikes[epoch].length, 'E10');

        uint256 strike = epochStrikes[epoch][strikeIndex];
        require(strike != 0, 'E12');

        bytes32 userStrike = keccak256(abi.encodePacked(msg.sender, strike));
        uint256 userStrikeDeposits = userEpochDeposits[epoch][userStrike];
        require(userStrikeDeposits > 0, 'E17');

        userQuoteTokenWithdrawAmount =
            (finalQuoteTokenBalancePerStrike[epoch][strike] *
                userStrikeDeposits) /
            totalEpochStrikeDeposits[epoch][strike];

        rewards =
            (crvToDistribute[epoch] *
                (totalEpochStrikeDeposits[epoch][strike] +
                    totalEpochStrikePremium[epoch][strike])) /
            (totalEpochDeposits[epoch] + totalEpochPremium[epoch]);

        rewards =
            (rewards * userStrikeDeposits) /
            totalEpochStrikeDeposits[epoch][strike];

        userEpochDeposits[epoch][userStrike] = 0;

        IERC20(getAddress('CRV')).safeTransfer(msg.sender, rewards);

        emit Withdraw(
            epoch,
            strike,
            msg.sender,
            userStrikeDeposits,
            userQuoteTokenWithdrawAmount,
            rewards
        );
    }

    /**
     * @notice Withdraws balances for a strike in a completed epoch
     * @param epoch Epoch to withdraw from
     * @param strikeIndex Index of strike
     * @return QuoteToken and rewards withdrawn
     */
    function withdraw(uint256 epoch, uint256 strikeIndex)
        external
        returns (uint256[2] memory)
    {
        (uint256 userQuoteTokenWithdrawAmount, uint256 rewards) = _withdraw(
            epoch,
            strikeIndex
        );

        quoteToken.safeTransfer(msg.sender, userQuoteTokenWithdrawAmount);

        return [userQuoteTokenWithdrawAmount, rewards];
    }

    /**
     * @notice Withdraws balances for a strike in a completed epoch in a specific coin of the 2Pool
     * @param epoch Epoch to withdraw from
     * @param strikeIndex Index of strike
     * @param minAmount The minimum amount to withdraw for the single coin
     * @param coinIndex Index of which coin to withdraw
     * @return coin amount and rewards withdrawn
     */
    function withdrawSpecificCoin(
        uint256 epoch,
        uint256 strikeIndex,
        uint256 minAmount,
        int256 coinIndex
    ) external returns (uint256[2] memory) {
        (uint256 userQuoteTokenWithdrawAmount, uint256 rewards) = _withdraw(
            epoch,
            strikeIndex
        );

        IERC20 coin = IERC20(quoteToken.coins(uint256(coinIndex)));

        uint256 _amount = quoteToken.remove_liquidity_one_coin(
            userQuoteTokenWithdrawAmount,
            int128(coinIndex),
            minAmount
        );

        coin.safeTransfer(msg.sender, _amount);

        return [_amount, rewards];
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

    /*==== VIEWS ====*/

    /// @notice Returns the volatility from the volatility oracle
    /// @param _strike Strike of the option
    function getVolatility(uint256 _strike) public view returns (uint256) {
        return
            IVolatilityOracle(getAddress('VolatilityOracle')).getVolatility(
                _strike
            );
    }

    /// @notice Calculate premium for an option
    /// @param _strike Strike price of the option
    /// @param _amount Amount of options
    /// @return premium in QuoteToken
    function calculatePremium(uint256 _strike, uint256 _amount)
        public
        view
        returns (uint256 premium)
    {
        uint256 currentPrice = getUsdPrice();
        premium = (IOptionPricing(getAddress('OptionPricing')).getOptionPrice(
            true, // isPut
            getMonthlyExpiryFromTimestamp(block.timestamp),
            _strike,
            currentPrice,
            getVolatility(_strike)
        ) * _amount);
        premium = ((premium * 1e10) / getLpPrice());
    }

    /// @notice Calculate Pnl
    /// @param price price of BaseToken
    /// @param strike strike price of the option
    /// @param amount amount of options
    function calculatePnl(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) public view returns (uint256) {
        return
            strike > price
                ? (((strike - price) * amount * 1e10) / getLpPrice())
                : 0;
    }

    /// @notice Calculate Fees for purchase
    /// @param price price of BaseToken
    /// @param strike strike price of the BaseToken option
    /// @param amount amount of options being bought
    /// @return the purchase fee in QuoteToken
    function calculatePurchaseFees(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) public view returns (uint256) {
        return ((IFeeStrategy(getAddress('FeeStrategy')).calculatePurchaseFees(
            price,
            strike,
            amount
        ) * 1e18) / getLpPrice());
    }

    /// @notice Calculate Fees for settlement of options
    /// @param settlementPrice settlement price of BaseToken
    /// @param pnl total pnl
    /// @param amount amount of options being settled
    function calculateSettlementFees(
        uint256 settlementPrice,
        uint256 pnl,
        uint256 amount
    ) public view returns (uint256) {
        return ((IFeeStrategy(getAddress('FeeStrategy'))
            .calculateSettlementFees(settlementPrice, pnl, amount) * 1e18) /
            getLpPrice());
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
     * @notice Returns total epoch puts purchased array for an epoch
     * @param epoch Target epoch
     */
    function getTotalEpochPutsPurchased(uint256 epoch)
        external
        view
        epochGreaterThanZero(epoch)
        returns (uint256[] memory)
    {
        uint256 length = epochStrikes[epoch].length;
        uint256[] memory _totalEpochPutsPurchased = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            _totalEpochPutsPurchased[i] = totalEpochPutsPurchased[epoch][
                epochStrikes[epoch][i]
            ];
        }

        return _totalEpochPutsPurchased;
    }

    /**
     * @notice Returns user epoch puts purchased array for an epoch
     * @param epoch Target epoch
     * @param user Address of the user
     */
    function getUserEpochPutsPurchased(uint256 epoch, address user)
        external
        view
        epochGreaterThanZero(epoch)
        returns (uint256[] memory)
    {
        uint256 length = epochStrikes[epoch].length;
        uint256[] memory _userEpochPutsPurchased = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            uint256 strike = epochStrikes[epoch][i];
            bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

            _userEpochPutsPurchased[i] = userEpochPutsPurchased[epoch][
                userStrike
            ];
        }

        return _userEpochPutsPurchased;
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
     * @notice Returns the price of the BaseToken in USD
     */
    function getUsdPrice() public view returns (uint256) {
        return uint256(IPriceOracle(getAddress('PriceOracle')).latestAnswer());
    }

    /**
     * @notice Returns the price of the Curve 2Pool LP token in 1e18
     */
    function getLpPrice() public view returns (uint256) {
        return quoteToken.get_virtual_price();
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
        require(msg.sender == getAddress('Governance'), 'E20');
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
//   "E14": "SSOV: Strike is higher than current price",
//   "E15": "SSOV: Option token balance is not enough",
//   "E16": "SSOV: Epoch must be expired",
//   "E17": "SSOV: User strike deposit amount must be greater than zero",
//   "E18": "SSOV: Deposit is only available between epochs",
//   "E19": "SSOV: Not bootstrapped",
//   "E20": "SSOV: Caller is not governance",
//   "E21": "SSOV: Expire delay tolerance exceeded",
// }

