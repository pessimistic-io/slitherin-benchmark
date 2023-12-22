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

interface IStaking {
    function stake( uint _amount, address _recipient ) external returns ( bool );
    function claim( address _recipient ) external;
}

contract PresaleWhitelisted {

    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint;
    using SafeERC20 for IERC20;



    /* ========== STRUCTS ========== */

    struct Term {
        uint whitelistedAmount; // how much is a user allowed to buy
        uint claimedAmount; // how much has a user already claimed
        uint boughtAmount; // how much has the user bought in total
        uint boughtAt; // when did the user pay for this
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
    uint public vestingPeriod;

    // price details
    uint public pricePerBase;
    uint public claimPrincipalPerBase;

    // principal maximum amount
    uint public principalMaximumSpend;
    uint public principalSpent;

    /* ========== CONSTRUCTOR ========== */
    
    constructor( 
        address _baseToken, 
        address _principalToken, 
        address _treasury, 
        address _DAO, 
        uint _vestingStart,
        uint _vestingPeriod,
        uint _pricePerBase,
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
        vestingPeriod = _vestingPeriod;

        require (_pricePerBase*1000 >= 10**IDecimals(_principalToken).decimals(), "Price must be at least 0.001");
        pricePerBase = _pricePerBase;

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

    function buy(uint _baseAmount) external {
        require(pricePerBase > 0, "Price must be set");
        uint _principalAmount = baseToPrincipalWhenBuying(_baseAmount);

        // spending cap for contract
        if (principalMaximumSpend > 0) {
            require(principalMaximumSpend > principalSpent, 'Contract maximum reached');
            uint remainingSpend = principalMaximumSpend - principalSpent;
            if (_principalAmount > remainingSpend) {
                // cap user to not exceed maximum spend
                _principalAmount = remainingSpend;
                _baseAmount = principalToBaseWhenBuying(_principalAmount);
            }
        }
        principalSpent += _principalAmount;

        require( buyableForInPrincipal( msg.sender ) >= _principalAmount, 'Paying for more than whitelisted for' );

        principalToken.safeTransferFrom( msg.sender, address( this ), _principalAmount ); // transfer principalToken payment in

        // calculate how much to keep
        uint retainAmount = baseToPrincipalWhenClaiming(_baseAmount);
        uint daoAmount = _principalAmount.sub(retainAmount);

        Term storage info = terms[ msg.sender ];
        info.boughtAmount = info.boughtAmount.add(_baseAmount);
        info.boughtAt = block.number > vestingStart ? block.number : vestingStart;
        require(info.whitelistedAmount >= info.boughtAmount, "Buying more than whitelisted for");

        // send off the DAO share
        principalToken.transfer(address(DAO), daoAmount);
    }

    /**
     *  @notice logic for claiming baseToken
     *  @param _baseAmount uint
     *  @return ToSend_ uint
     */
    function _claim( uint _baseAmount ) internal returns ( uint ToSend_ ) {
        uint principalAmount = baseToPrincipalWhenClaiming(_baseAmount);
        principalToken.approve( address( treasury ), principalAmount ); // approve and
        ToSend_ = treasury.deposit( principalAmount, address( principalToken ), 0 ); // deposit into treasury, receive baseToken
        require(ToSend_ == _baseAmount, 'ToSend needs to match baseAmount');

        // ensure claim is within bounds
        require( claimableForInBase( msg.sender ) >= _baseAmount, 'Not enough vested' );

        // add amount to tracked balance
        Term storage info = terms[ msg.sender ];
        info.claimedAmount = info.claimedAmount.add(_baseAmount);
    }

    /**
     *  @notice allows address to push terms to new address
     *  @param _newAddress address
     */
    function pushWalletChange( address _newAddress ) external {
        require( terms[ msg.sender ].whitelistedAmount != 0 );
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



    /* ========== VIEW FUNCTIONS ========== */

    function claimableForInBase( address _address ) public view returns (uint) {
        Term memory info = terms[ _address ];

        if (block.number < info.boughtAt) {
            return 0; // vesting not yet begun
        }

        if (block.number > info.boughtAt.add(vestingPeriod)) {
            // maximum amount as vesting is done
            return info.boughtAmount.sub(info.claimedAmount);
        }

        // calculate based on vesting
        return info.boughtAmount.mul(uint(block.number).sub(info.boughtAt)).div(vestingPeriod).sub(info.claimedAmount); //.mul(pricePerBase).div(10**IDecimals(address(baseToken)).decimals());
    }
    function claimableForInPrincipal( address _address ) public view returns (uint) {
        return baseToPrincipalWhenClaiming(claimableForInBase(_address));
    }
    function baseToPrincipalWhenClaiming(uint _baseAmount) public view returns (uint) {
        return _baseAmount.mul(claimPrincipalPerBase).div(10**IDecimals(address(baseToken)).decimals());
    }

    function buyableForInBase( address _address ) public view returns (uint) {
        if (pricePerBase == 0) {
            return 0; // nobody can buy anything
        }

        Term memory info = terms[ _address ];

        return info.whitelistedAmount.sub(info.boughtAmount);
    }
    function buyableForInPrincipal( address _address ) public view returns (uint) {
        return baseToPrincipalWhenBuying(buyableForInBase(_address));
    }
    function baseToPrincipalWhenBuying(uint _baseAmount) public view returns (uint) {
        return _baseAmount.mul(pricePerBase).div(10**IDecimals(address(baseToken)).decimals());
    }
    function principalToBaseWhenBuying(uint _principalAmount) public view returns (uint) {
        return _principalAmount.mul(10**IDecimals(address(baseToken)).decimals()).div(pricePerBase);
    }

    /**
     *  @notice view baseToken claimed by address. baseToken decimals (9).
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
     *  @param _addresses addresses
     *  @param _whitelistedAmounts uints
     */
    function setTerms(address[] memory _addresses, uint[] memory _whitelistedAmounts ) external {
        require( msg.sender == owner, "Sender is not owner" );
        for (uint i = 0;  i < _addresses.length;  ++i) {
            require( _whitelistedAmounts[i] >= terms[ _addresses[i] ].boughtAmount, "Cannot lower whitelist below bought amount" );

            terms[ _addresses[i] ].whitelistedAmount = _whitelistedAmounts[i];
        }
    }

    function setVesting(uint _vestingPeriod) external {
        require( msg.sender == owner, "Sender is not owner" );
        vestingPeriod = _vestingPeriod;
    }


    function setPrincipalMaximumSpend(uint _principalMaximumSpend) external {
        require( msg.sender == owner, "Sender is not owner" );
        principalMaximumSpend = _principalMaximumSpend;
    }


    function setPricePerBase(uint _pricePerBase) external {
        require( msg.sender == owner, "Sender is not owner" );
        require (_pricePerBase*1000 >= 10**IDecimals(address(principalToken)).decimals() || _pricePerBase == 0, "Price must be at least 0.001");
        pricePerBase = _pricePerBase;
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
