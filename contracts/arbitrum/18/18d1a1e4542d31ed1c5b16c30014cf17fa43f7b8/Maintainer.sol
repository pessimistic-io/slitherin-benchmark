// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

import "./SafeERC20.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./Address.sol";


interface IDecimals {
    function decimals() external view returns (uint8);
}

interface ITreasury {
    function deposit( uint _amount, address _token, uint _profit ) external returns ( uint );
}

contract Maintainer {

    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint;
    using SafeERC20 for IERC20;



    /* ========== STRUCTS ========== */

    struct Term {
        uint factor; // how much is a user allowed to buy
        uint claimedAmount; // how much has a user already claimed
        uint maximumAmount; // how much the user can claim at most, or 0 if unlimited
        uint vestingPeriod; // how many blocks the full factor will mature over
    }

    /* ========== STATE VARIABLES ========== */
    
    address owner; // can set terms
    address newOwner; // push/pull model for changing ownership
    
    IERC20 immutable baseToken; // claim token
    IERC20 immutable principalToken; // payment token

    ITreasury immutable treasury; // mints claim token

    address immutable DAO; // holds non-circulating supply
    
    mapping( address => Term ) public terms; // tracks address info
    
    mapping( address => address ) public walletChange; // facilitates address change

    // vesting details
    uint public vestingStart;

    // misc details
    uint public claimPrincipalPerBase;

    uint immutable public FACTOR_MAXIMUM = 1_000_000;


    /* ========== CONSTRUCTOR ========== */
    
    constructor( 
        address _baseToken, 
        address _principalToken, 
        address _treasury, 
        address _DAO, 
        uint _vestingStart,
        uint _claimPrincipalPerBase
    ) {
        owner = msg.sender;

        require( _baseToken != address(0) );
        baseToken = IERC20( _baseToken );

        require( _principalToken != address(0) );
        principalToken = IERC20( _principalToken );

        require( _treasury != address(0) );
        treasury = ITreasury( _treasury );

        require( _DAO != address(0) );
        DAO = _DAO;

        vestingStart = _vestingStart;
        claimPrincipalPerBase = _claimPrincipalPerBase;
    }


    /* ========== USER FUNCTIONS ========== */
    
    /**
     *  @notice allows wallet to claim baseToken
     *  @param _amount uint
     */
    function claim( uint _amount ) external {
        baseToken.safeTransfer( msg.sender, _claim( _amount ) ); // send claimed to sender
    }

    /**
     *  @notice logic for claiming baseToken
     *  @param _baseAmount uint How many baseToken being claimed.
     *  @return baseAmount_ uint The amount of baseToken claimed.
     */
    function _claim( uint _baseAmount ) internal returns ( uint baseAmount_ ) {
        uint principalAmount = baseToPrincipalWhenClaiming(_baseAmount);

        principalToken.safeTransferFrom( msg.sender, address( this ), principalAmount ); // transfer principalToken payment in

        principalToken.approve( address( treasury ), principalAmount ); // approve and
        baseAmount_ = treasury.deposit( principalAmount, address( principalToken ), 0 ); // deposit into treasury, receive baseToken
        require(baseAmount_ == _baseAmount, 'ToSend needs to match baseAmount');

        // ensure claim is within bounds
        require( claimableForInBase( msg.sender ) >= _baseAmount, 'Not enough vested' );

        // add amount to tracked balance
        Term storage info = terms[ msg.sender ];
        info.claimedAmount = info.claimedAmount.add(baseAmount_);
    }

    /**
     *  @notice allows address to push terms to new address
     *  @param _newAddress address
     */
    function pushWalletChange( address _newAddress ) external {
        require( terms[ msg.sender ].factor != 0 );
        walletChange[ msg.sender ] = _newAddress;
    }
    
    /**
     *  @notice allows new address to pull terms
     *  @param _oldAddress address
     */
    function pullWalletChange( address _oldAddress ) external {
        require( walletChange[ _oldAddress ] == msg.sender, "wallet did not push" );
        
        walletChange[ _oldAddress ] = address(0);
        terms[ msg.sender ] = terms[ _oldAddress ];
        delete terms[ _oldAddress ];
    }


    function maxPayout( uint factor ) public view returns ( uint ) {
        return IERC20( baseToken ).totalSupply().mul( factor ).div( FACTOR_MAXIMUM );
    }


    /* ========== VIEW FUNCTIONS ========== */


    function interpolateZeroToMax(uint inputAmount, uint interpolateStart, uint interpolateLength, uint interpolateAmount) internal pure returns (uint) {
        if (interpolateAmount < interpolateStart) {
            return 0; // interpolation not started yet
        }

        if (interpolateAmount > interpolateStart.add(interpolateLength)) {
            return inputAmount; // interpolation at end
        }

        // calculate based on vesting
        return inputAmount.mul(interpolateAmount.sub(interpolateStart)).div(interpolateLength);
    }


    /**
     *  @notice View function. Returns amount of baseToken claimable for address, using principalToken decimals (18).
     *  @param _address address
     *  @return uint
     */
    function claimableForInBase( address _address ) public view returns (uint) {
        // how much is available by factor?
        Term memory info = terms[ _address ];
        uint claimAmount = maxPayout(info.factor);

        // apply vesting
        claimAmount = interpolateZeroToMax(claimAmount, vestingStart, info.vestingPeriod, block.number);

        // account for maximums
        if (info.maximumAmount < claimAmount && info.maximumAmount > 0) {
            claimAmount = info.maximumAmount;
        }

        // account for amount already claimed
        if (info.claimedAmount > claimAmount) {
            claimAmount = 0;
        } else {
            claimAmount = claimAmount.sub(info.claimedAmount);
        }

        return claimAmount;
    }
    function claimableForInPrincipal( address _address ) public view returns (uint) {
        return baseToPrincipalWhenClaiming(claimableForInBase(_address));
    }
    function baseToPrincipalWhenClaiming(uint _baseAmount) public view returns (uint) {
        return _baseAmount.mul(claimPrincipalPerBase).div(10**IDecimals(address(baseToken)).decimals());
    }


    /**
     *  @notice View function. Amount of baseToken claimed by address, using baseToken decimals (9).
     *  @param _address address
     *  @return uint
     */
    function claimed( address _address ) public view returns ( uint ) {
        return terms[_address].claimedAmount;
    }


    /* ========== OWNER FUNCTIONS ========== */

    /**
     *  @notice set terms for new address
     *  @notice cannot lower for address or exceed maximum total allocation
     *  @param _addresses address[]
     *  @param _factors uint[] As a factor of total supply, divided by 100,000
     *  @param _maximums uint[] Maximum amount of baseToken user can claim
     *  @param _vestingPeriods uint[] How many blocks it is vested over
     */
    function setTerms(address[] memory _addresses, uint[] memory _factors, uint[] memory _maximums, uint[] memory _vestingPeriods ) external {
        require( msg.sender == owner, "Sender is not owner" );
        for (uint i = 0;  i < _addresses.length;  ++i) {
            Term storage term = terms[ _addresses[i] ];

            require( _factors[i] >= term.factor, "Cannot lower factor" );
            require( _maximums[i] >= term.maximumAmount && (term.factor == 0 || term.maximumAmount > 0), "Cannot lower maximum" );
            require( _vestingPeriods[i] >= term.vestingPeriod, "Cannot raise vestingPeriod" );
            require( _factors[i] <= FACTOR_MAXIMUM.div(10), "Factor too large" );

            terms[ _addresses[i] ].factor = _factors[i];
            terms[ _addresses[i] ].maximumAmount = _maximums[i];
            terms[ _addresses[i] ].vestingPeriod = _vestingPeriods[i];
        }
    }

    /**
     *  @notice push ownership of contract
     *  @param _newOwner address
     */
    function pushOwnership( address _newOwner ) external {
        require( msg.sender == owner, "Sender is not owner" );
        require( _newOwner != address(0) );
        newOwner = _newOwner;
    }
    
    /**
     *  @notice pull ownership of contract
     */
    function pullOwnership() external {
        require( msg.sender == newOwner );
        owner = newOwner;
        newOwner = address(0);
    }

    /**
     *  @notice renounce ownership of contract (no owner)
     */
     function renounceOwnership() external {
         require( msg.sender == owner, "Sender is not owner" );
         owner = address(0);
         newOwner = address(0);
     }
}
