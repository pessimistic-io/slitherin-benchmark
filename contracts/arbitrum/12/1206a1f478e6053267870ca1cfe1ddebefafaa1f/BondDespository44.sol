// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./SafeERC20.sol";
import "./FixedPoint.sol";
import "./IsVim.sol";
import "./ITreasury.sol";
import "./IBondCalculator.sol";
import "./IStaking.sol";
import "./IDiscount.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";

contract BondDepository44 is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using FixedPoint for *;
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    /* ======== EVENTS ======== */

    event BondCreated( uint deposit, uint indexed payout, uint indexed expires, uint indexed priceInUSD );
    event BondRedeemed( address indexed recipient, uint payout, uint remaining );
    event BondPriceChanged( uint indexed priceInUSD, uint indexed internalPrice, uint indexed debtRatio );
    event ControlVariableAdjustment( uint initialBCV, uint newBCV, uint adjustment, bool addition );
    event SetAdjustment(bool _addition, uint _increment, uint _target, uint _buffer);

    /* ======== STATE VARIABLES ======== */

    address public Vim; // token given as payment for bond
    address public principle; // token used to create bond
    address public treasury; // mints Vim when receives principle
    address public DAO; // receives profit share from bond

    bool public isLiquidityBond; // LP and Reserve bonds are treated slightly different
    address public bondCalculator; // calculates value of LP tokens

    address public staking; // to auto-stake payout

    Terms public terms; // stores terms for new bonds
    Adjust public adjustment; // stores adjustment to BCV data

    mapping( address => Bond ) public bondInfo; // stores bond information for depositors

    uint public totalDebt; // total value of outstanding bonds; used for pricing
    uint public lastDecay; // reference block for debt decay

    address public sVim;

    uint public minPayout;

    address public discount;

    uint public balance;

    /* ======== STRUCTS ======== */

    // Info for creating new bonds
    struct Terms {
        uint controlVariable; // scaling variable for price
        uint vestingTerm; // in blocks
        uint minimumPrice; // vs principle value
        uint maxPayout; // in thousandths of a %. i.e. 500 = 0.5%
        uint fee; // as % of bond payout, in hundreths. ( 500 = 5% = 0.05 for every 1 paid)
        uint maxDebt; // 9 decimal debt ratio, max % total supply created as debt
    }

    // Info for bond holder
    struct Bond {
        uint payout;   // sVim remaining to be paid
        uint vesting; // Time left to vest
        uint lastTimestamp; // Last interaction
        uint pricePaid; // In USDT, for front end viewing
    }

    // Info for incremental adjustments to control variable 
    struct Adjust {
        bool add; // addition or subtraction
        uint rate; // increment
        uint target; // BCV when adjustment finished
        uint buffer; // minimum length (in blocks) between adjustments
        uint lastTimestamp; // timestamp when last adjustment made
    }

    /* ======== INITIALIZATION ======== */

   function initialize(
        address _Vim,
        address _sVim,
        address _principle,
        address _treasury, 
        address _DAO, 
        address _bondCalculator,
        address _staking
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        require( _Vim != address(0) );
        Vim = _Vim;
        require( _sVim != address(0) );
        sVim = _sVim;
        require( _principle != address(0) );
        principle = _principle;
        require( _treasury != address(0) );
        treasury = _treasury;
        require( _DAO != address(0) );
        DAO = _DAO;
        // bondCalculator should be address(0) if not LP bond
        bondCalculator = _bondCalculator;
        isLiquidityBond = ( _bondCalculator != address(0) );
        require( _staking != address(0) );
        staking = _staking;
        IERC20( Vim ).approve( staking, uint(~0) );
        _pause();
    }

    /**
     *  @notice initializes bond parameters
     *  @param _controlVariable uint
     *  @param _vestingTerm uint
     *  @param _minimumPrice uint
     *  @param _maxPayout uint
     *  @param _fee uint
     *  @param _maxDebt uint
     *  @param _initialDebt uint
     */
    function initializeBondTerms( 
        uint _controlVariable, 
        uint _vestingTerm,
        uint _minimumPrice,
        uint _maxPayout,
        uint _fee,
        uint _maxDebt,
        uint _initialDebt
    ) external onlyOwner() {
        require( terms.controlVariable == 0, "Bonds must be initialized from 0" );
        terms = Terms ({
            controlVariable: _controlVariable,
            vestingTerm: _vestingTerm,
            minimumPrice: _minimumPrice,
            maxPayout: _maxPayout,
            fee: _fee,
            maxDebt: _maxDebt
        });
        totalDebt = _initialDebt;
        lastDecay = block.timestamp;
    }
    
    /* ======== POLICY FUNCTIONS ======== */

    enum PARAMETER { VESTING, PAYOUT, FEE, DEBT, MINPRICE}
    /**
     *  @notice set parameters for new bonds
     *  @param _parameter PARAMETER
     *  @param _input uint
     */
    function setBondTerms ( PARAMETER _parameter, uint _input ) external onlyOwner() {
        if ( _parameter == PARAMETER.VESTING ) { // 0
            require( _input >= 3600 * 36, "Vesting must be longer than 36 hours" );
            terms.vestingTerm = _input;
        } else if ( _parameter == PARAMETER.PAYOUT ) { // 1
            require( _input <= 1000, "Payout cannot be above 1 percent" );
            terms.maxPayout = _input;
        } else if ( _parameter == PARAMETER.FEE ) { // 2
            require( _input <= 10000, "DAO fee cannot exceed payout" );
            terms.fee = _input;
        } else if ( _parameter == PARAMETER.DEBT ) { // 3
            terms.maxDebt = _input;
        } else if (_parameter == PARAMETER.MINPRICE) { // 4
            terms.minimumPrice = _input;
        }
    }

    /**
     *  @notice set control variable adjustment
     *  @param _addition bool
     *  @param _increment uint
     *  @param _target uint
     *  @param _buffer uint
     */
    function setAdjustment ( 
        bool _addition,
        uint _increment, 
        uint _target,
        uint _buffer 
    ) external onlyOwner() {
        adjustment = Adjust({
            add: _addition,
            rate: _increment,
            target: _target,
            buffer: _buffer,
            lastTimestamp: block.timestamp
        });
        emit SetAdjustment(_addition, _increment, _target, _buffer);
    }

    /**
     *  @notice set contract for auto stake
     *  @param _staking address
     */
    function setStaking( address _staking ) external onlyOwner() {
        require( _staking != address(0) );
        staking = _staking;
        IERC20( Vim ).approve( staking, uint(~0) );
    }

    function setMinPayOut( uint _minPayout ) external onlyOwner() {
        minPayout = _minPayout;
    }

    function setDiscount( address _discount ) external onlyOwner() {
        require(_discount != address(0));
        discount = _discount;
    }

    /**
     *  @notice deposit bond
     *  @param _amount uint
     *  @param _maxPrice uint
     *  @param _depositor address
     *  @param _referrer address
     *  @return uint
     */
    function deposit( 
        uint _amount, 
        uint _maxPrice,
        address _depositor,
        address _referrer
    ) external nonReentrant whenNotPaused returns ( uint ) {
        require( _depositor != address(0), "Invalid address" );

        decayDebt();
        require( totalDebt <= terms.maxDebt, "Max capacity reached" );
        
        uint priceInUSD = bondPriceInUSD(); // Stored in bond info
        uint nativePrice = _bondPrice();

        require( _maxPrice >= nativePrice, "Slippage limit: more than max price" ); // slippage protection

        uint value = ITreasury( treasury ).valueOf( principle, _amount );
        uint payout = payoutFor( value, msg.sender ); // payout to bonder is computed

        require( payout >= 10000000, "Bond too small" ); // must be > 0.01 Vim ( underflow protection )
        require( payout <= maxPayout(), "Bond too large"); // size protection because there is no slippage

        // profits are calculated
        uint fee = payout.mul( terms.fee ).div( 10000 );
        uint profit = value.sub( payout ).sub( fee );

        /**
            principle is transferred in
            approved and
            deposited into the treasury, returning (_amount - profit) Vim
         */
        IERC20( principle ).safeTransferFrom( msg.sender, address(this), _amount );
        IERC20( principle ).approve( address( treasury ), _amount );
        ITreasury( treasury ).deposit( _amount, principle, profit, _referrer );
        
        if ( fee != 0 ) { // fee is transferred to dao
            IERC20( Vim ).safeTransfer( DAO, fee ); 
        }
        
        // total debt is increased
        totalDebt = totalDebt.add( value ); 
        balance = balance.add( _amount );
                
        // depositor info is stored
        bondInfo[ _depositor ] = Bond({ 
            payout: bondInfo[ _depositor ].payout.add(IsVim( sVim ).gonsForBalance(payout)),
            vesting: terms.vestingTerm,
            lastTimestamp: block.timestamp,
            pricePaid: priceInUSD
        });

        IStaking( staking ).stake( payout, address(this) );

        // indexed events are emitted
        emit BondCreated( _amount, payout, block.timestamp.add( terms.vestingTerm ), priceInUSD );
        emit BondPriceChanged( bondPriceInUSD(), _bondPrice(), debtRatio() );

        adjust(); // control variable is adjusteds
        return payout; 
    }

    /** 
     *  @notice redeem bond for user
     *  @param _recipient address
     *  @return uint
     */ 
    function redeem( address _recipient ) external nonReentrant returns ( uint ) {        
        Bond memory info = bondInfo[ _recipient ];
        uint percentVested = percentVestedFor( _recipient ); // (blocks since last interaction / vesting term remaining)

        if ( percentVested >= 1e8 ) { // if fully vested
            delete bondInfo[ _recipient ]; // delete user info
            uint amt = IsVim( sVim ).balanceForGons( info.payout );
            emit BondRedeemed( _recipient, amt, 0 ); // emit bond data
            IERC20( sVim ).safeTransfer(_recipient, amt);

        } else { // if unfinished
            // calculate payout vested
            uint payout = info.payout.div( 1e8 ).mul( percentVested );

            // store updated deposit info
            bondInfo[ _recipient ] = Bond({
                payout: info.payout.sub( payout ),
                vesting: info.vesting.sub( block.timestamp.sub( info.lastTimestamp ) ),
                lastTimestamp: block.timestamp,
                pricePaid: info.pricePaid
            });

            uint amt = IsVim( sVim ).balanceForGons( payout );
            uint leftAmt = IsVim( sVim ).balanceForGons( bondInfo[ _recipient ].payout );
            emit BondRedeemed( _recipient, amt, leftAmt );
            IERC20( sVim ).safeTransfer(_recipient, amt);
        }
    }

    /* ======== INTERNAL HELPER FUNCTIONS ======== */

    /**
     *  @notice makes incremental adjustment to control variable
     */
    function adjust() internal {
        uint blockCanAdjust = adjustment.lastTimestamp.add( adjustment.buffer );
        if( adjustment.rate != 0 && block.timestamp >= blockCanAdjust ) {
            uint initial = terms.controlVariable;
            if ( adjustment.add ) {
                terms.controlVariable = terms.controlVariable.add( adjustment.rate );
                if ( terms.controlVariable >= adjustment.target ) {
                    adjustment.rate = 0;
                }
            } else {
                terms.controlVariable = terms.controlVariable.sub( adjustment.rate );
                if ( terms.controlVariable <= adjustment.target ) {
                    adjustment.rate = 0;
                }
            }
            adjustment.lastTimestamp = block.timestamp;
            emit ControlVariableAdjustment( initial, terms.controlVariable, adjustment.rate, adjustment.add );
        }
    }

    /**
     *  @notice reduce total debt
     */
    function decayDebt() internal {
        totalDebt = totalDebt.sub( debtDecay() );
        lastDecay = block.timestamp;
    }

    /* ======== VIEW FUNCTIONS ======== */

    /**
     *  @notice determine maximum bond size
     *  @return uint
     */
    function maxPayout() public view returns ( uint ) {
        return IERC20( Vim ).totalSupply().mul( terms.maxPayout ).div( 100000 );
    }

    function maxDebt() public view returns ( uint ) {
        return terms.maxDebt;
    }

    /**
     *  @notice calculate interest due for new bond
     *  @param _value uint
     *  @return uint
     */
    function payoutFor( uint _value ) public view returns ( uint ) {
        return FixedPoint.fraction( _value, bondPrice() ).decode112with18().div( 1e16 );
    }

    function payoutFor( uint _value, address _user ) public view returns ( uint ) {
        return FixedPoint.fraction( _value, bondPrice(_user) ).decode112with18().div( 1e16 );
    }

    /**
     *  @notice calculate current bond premium
     *  @return price_ uint
     */
    function bondPrice() public view returns ( uint price_ ) {        
        price_ = terms.controlVariable.mul( debtRatio() ).add( 1000000000 ).div( 1e7 );
        if ( price_ < terms.minimumPrice ) {
            price_ = terms.minimumPrice;
        }
    }

    function bondPrice(address _user) public view returns ( uint price_ ) {        
        price_ = terms.controlVariable.mul( debtRatio() ).add( 1000000000 ).div( 1e7 );
        if ( price_ < terms.minimumPrice ) {
            price_ = terms.minimumPrice;
        }

        price_ = price_ * discountOf(_user) / 100;
    }

    /**
     *  @notice calculate current bond price and remove floor if above
     *  @return price_ uint
     */
    function _bondPrice() internal returns ( uint price_ ) {
        price_ = terms.controlVariable.mul( debtRatio() ).add( 1000000000 ).div( 1e7 );
        if ( price_ < terms.minimumPrice ) {
            price_ = terms.minimumPrice;        
        } else if ( terms.minimumPrice != 0 ) {
            terms.minimumPrice = 0;
        }
    }

    /**
     *  @notice converts bond price to USDT value
     *  @return price_ uint
     */
    function bondPriceInUSD() public view returns ( uint price_ ) {
        if( isLiquidityBond ) {
            price_ = bondPrice().mul( IBondCalculator( bondCalculator ).markdown( principle ) ).div( 100 );
        } else {
            price_ = bondPrice().mul( 10 ** IERC20( principle ).decimals() ).div( 100 );
        }
    }

    function bondPriceInUSD(address _user) public view returns ( uint price_ ) {
        if( isLiquidityBond ) {
            price_ = bondPrice(_user).mul( IBondCalculator( bondCalculator ).markdown( principle ) ).div( 100 );
        } else {
            price_ = bondPrice(_user).mul( 10 ** IERC20( principle ).decimals() ).div( 100 );
        }
    }

    /**
     *  @notice calculate current ratio of debt to Vim supply
     *  @return debtRatio_ uint
     */
    function debtRatio() public view returns ( uint debtRatio_ ) {   
        uint supply = IERC20( Vim ).totalSupply();
        if (supply == 0) {
            return 0;
        }
        
        debtRatio_ = FixedPoint.fraction( 
            currentDebt().mul( 1e9 ), 
            supply
        ).decode112with18().div( 1e18 );
    }

    /**
     *  @notice debt ratio in same terms for reserve or liquidity bonds
     *  @return uint
     */
    function standardizedDebtRatio() external view returns ( uint ) {
        if ( isLiquidityBond ) {
            return debtRatio().mul( IBondCalculator( bondCalculator ).markdown( principle ) ).div( 1e9 );
        } else {
            return debtRatio();
        }
    }

    /**
     *  @notice calculate debt factoring in decay
     *  @return uint
     */
    function currentDebt() public view returns ( uint ) {
        return totalDebt.sub( debtDecay() );
    }

    /**
     *  @notice amount to decay total debt by
     *  @return decay_ uint
     */
    function debtDecay() public view returns ( uint decay_ ) {
        uint timeSinceLast = block.timestamp.sub( lastDecay );
        decay_ = totalDebt.mul( timeSinceLast ).div( terms.vestingTerm );
        if ( decay_ > totalDebt ) {
            decay_ = totalDebt;
        }
    }

    /**
     *  @notice calculate how far into vesting a depositor is
     *  @param _depositor address
     *  @return percentVested_ uint
     */
    function percentVestedFor( address _depositor ) public view returns ( uint percentVested_ ) {
        Bond memory bond = bondInfo[ _depositor ];
        uint blocksSinceLast = block.timestamp.sub( bond.lastTimestamp );
        uint vesting = bond.vesting;

        if ( vesting > 0 ) {
            percentVested_ = blocksSinceLast.mul( 1e8 ).div( vesting );
        } else {
            percentVested_ = 0;
        }
    }

    /**
     *  @notice calculate amount of sVim available for claim by depositor
     *  @param _depositor address
     *  @return pendingPayout_ uint
     */
    function pendingPayoutFor( address _depositor ) external view returns ( uint pendingPayout_ ) {
        uint percentVested = percentVestedFor( _depositor );
        uint payout = bondInfo[ _depositor ].payout;

        if ( percentVested >= 1e8 ) {
            pendingPayout_ = payout;
        } else {
            pendingPayout_ = payout.div( 1e8 ).mul( percentVested );
        }

        pendingPayout_ = IsVim( sVim ).balanceForGons( pendingPayout_ );
    }

    /* ======= AUXILLIARY ======= */

    /**
     *  @notice allow anyone to send lost tokens (excluding principle or Vim) to the DAO
     *  @return bool
     */
    function recoverLostToken( address _token ) external returns ( bool ) {
        require( _token != Vim );
        require( _token != principle );
        IERC20( _token ).safeTransfer( DAO, IERC20( _token ).balanceOf( address(this) ) );
        return true;
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function discountOf(address _user) public view returns(uint256) {
        if (discount != address(0)) {
            return IDiscount(discount).discountOf(_user);
        }
        return 100;
    }

    function setBalance(uint _bal) external onlyOwner {
        if (_bal > 0) {
            balance = _bal;
        } else {
            balance = IERC20(principle).balanceOf(treasury);
        }
    }
}
