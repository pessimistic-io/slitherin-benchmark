// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./SafeERC20.sol";
import "./IsVim.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

interface IWarmup {
    function retrieve( address staker_, uint amount_ ) external;
}

interface IDistributor {
    function distribute() external returns ( bool );
}

contract Staking is OwnableUpgradeable, ReentrancyGuardUpgradeable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public Vim;
    address public sVim;

    struct Epoch {
        uint length;
        uint number;
        uint endTimestamp;
        uint distribute;
    }
    Epoch public epoch;

    address public distributor;
    
    address public locker;
    uint public totalBonus;
    
    address public warmupContract;
    uint public warmupPeriod;

    event SetWarmup( uint _warmupPeriod );
    event SetContract( CONTRACTS _contract, address _address );

    /* ======== INITIALIZATION ======== */
    
    function initialize(
        address _Vim, 
        address _sVim, 
        uint _epochLength,
        uint _firstEpochNumber,
        uint _firstEpochTimestamp
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        require( _Vim != address(0) );
        Vim = _Vim;
        require( _sVim != address(0) );
        sVim = _sVim;
        
        epoch = Epoch({
            length: _epochLength,
            number: _firstEpochNumber,
            endTimestamp: (_firstEpochTimestamp == 0 ? block.timestamp + _epochLength : _firstEpochTimestamp),
            distribute: 0
        });
    }

    struct Claim {
        uint deposit;
        uint gons;
        uint expiry;
        bool lock; // prevents malicious delays
    }
    mapping( address => Claim ) public warmupInfo;

    /**
        @notice stake Vim to enter warmup
        @param _amount uint
        @return bool
     */
    function stake( uint _amount, address _recipient ) external nonReentrant returns ( bool ) {
        require(_recipient != address(0), "Recipient undefined");
        
        Claim memory info = warmupInfo[ _recipient ];
        require( !info.lock, "Deposits for account are locked" );

        rebase();
        
        IERC20( Vim ).safeTransferFrom( msg.sender, address(this), _amount );

        if (warmupPeriod > 0) {
            warmupInfo[ _recipient ] = Claim ({
                deposit: info.deposit.add( _amount ),
                gons: info.gons.add( IsVim( sVim ).gonsForBalance( _amount ) ),
                expiry: epoch.number.add( warmupPeriod ),
                lock: false
            });
        
            IERC20( sVim ).safeTransfer( warmupContract, _amount );
        } else {
            IERC20( sVim ).safeTransfer(_recipient, _amount);
        }
        
        return true;
    }

    /**
        @notice retrieve sVim from warmup
        @param _recipient address
     */
    function claim ( address _recipient ) public nonReentrant {
        Claim memory info = warmupInfo[ _recipient ];
        if ( info.gons > 0 && epoch.number >= info.expiry && info.expiry != 0 ) {
            delete warmupInfo[ _recipient ];
            IWarmup( warmupContract ).retrieve( _recipient, IsVim( sVim ).balanceForGons( info.gons ) );
        }
    }

    /**
        @notice forfeit sVim in warmup and retrieve Vim
     */
    function forfeit() external nonReentrant {
        Claim memory info = warmupInfo[ msg.sender ];
        if (info.gons > 0) {
            delete warmupInfo[ msg.sender ];

            IWarmup( warmupContract ).retrieve( address(this), IsVim( sVim ).balanceForGons( info.gons ) );
            IERC20( Vim ).safeTransfer( msg.sender, info.deposit );
        }
    }

    /**
        @notice prevent new deposits to address (protection from malicious activity)
     */
    function toggleDepositLock() external {
        warmupInfo[ msg.sender ].lock = !warmupInfo[ msg.sender ].lock;
    }

    /**
        @notice redeem sVim for Vim
        @param _amount uint
        @param _trigger bool
     */
    function unstake( uint _amount, bool _trigger ) external nonReentrant {
        require(_amount <= contractBalance(), "Insufficient contract balance");
        if ( _trigger ) {
            rebase();
        }
        IERC20( sVim ).safeTransferFrom( msg.sender, address(this), _amount );
        IERC20( Vim ).safeTransfer( msg.sender, _amount );
    }

    /**
        @notice returns the sVim index, which tracks rebase growth
        @return uint
     */
    function index() public view returns ( uint ) {
        return IsVim( sVim ).index();
    }

    /**
        @notice trigger rebase if epoch over
     */
    function rebase() public {
        if( epoch.endTimestamp <= block.timestamp ) {
            IsVim( sVim ).rebase( epoch.distribute, epoch.number );

            epoch.endTimestamp = epoch.endTimestamp.add( epoch.length );
            epoch.number++;
            
            if ( distributor != address(0) ) {
                IDistributor( distributor ).distribute();
            }

            uint balance = contractBalance();
            uint staked = IsVim( sVim ).circulatingSupply();

            if( balance <= staked ) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = balance.sub( staked );
            }
        }
    }

    /**
        @notice returns contract Vim holdings, including bonuses provided
        @return uint
     */
    function contractBalance() public view returns ( uint ) {
        return IERC20( Vim ).balanceOf( address(this) ).add( totalBonus );
    }

    /**
        @notice provide bonus to locked staking contract
        @param _amount uint
     */
    function giveLockBonus( uint _amount ) external {
        require( msg.sender == locker );
        totalBonus = totalBonus.add( _amount );
        IERC20( sVim ).safeTransfer( locker, _amount );
    }

    /**
        @notice reclaim bonus from locked staking contract
        @param _amount uint
     */
    function returnLockBonus( uint _amount ) external {
        require( msg.sender == locker );
        totalBonus = totalBonus.sub( _amount );
        IERC20( sVim ).safeTransferFrom( locker, address(this), _amount );
    }

    enum CONTRACTS { DISTRIBUTOR, WARMUP, LOCKER }

    /**
        @notice sets the contract address for LP staking
        @param _contract address
     */
    function setContract( CONTRACTS _contract, address _address ) external onlyOwner() {
        if( _contract == CONTRACTS.DISTRIBUTOR ) { // 0
            distributor = _address;
        } else if ( _contract == CONTRACTS.WARMUP ) { // 1
            require( warmupContract == address( 0 ), "Warmup cannot be set more than once" );
            warmupContract = _address;
        } else if ( _contract == CONTRACTS.LOCKER ) { // 2
            require( locker == address(0), "Locker cannot be set more than once" );
            locker = _address;
        }
        emit SetContract(_contract, _address);
    }
    
    /**
     * @notice set warmup period for new stakers
     * @param _warmupPeriod uint
     */
    function setWarmup( uint _warmupPeriod ) external onlyOwner() {
        warmupPeriod = _warmupPeriod;
        emit SetWarmup(_warmupPeriod);
    }

    function setFirstEpochTimestamp(uint256 _firstEpochTimestamp) external onlyOwner() {
        require(epoch.number == 0);
        epoch.endTimestamp = (_firstEpochTimestamp == 0 ? block.timestamp + epoch.length : _firstEpochTimestamp);
    }
}
