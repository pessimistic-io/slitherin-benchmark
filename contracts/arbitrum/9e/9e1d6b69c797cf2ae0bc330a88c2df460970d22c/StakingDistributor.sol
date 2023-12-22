
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./SafeERC20.sol";
import "./ITreasury.sol";
import "./OwnableUpgradeable.sol";

contract Distributor is OwnableUpgradeable {
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    
    /* ====== VARIABLES ====== */

    address public Vim;
    address public treasury;
    
    uint public epochLength;
    uint public nextEpochTimestamp;
    
    mapping( uint => Adjust ) public adjustments;

    event SetAdjustment( uint _index, bool _add, uint _rate, uint _target );
    event AddRecipient( address _recipient, uint _rewardRate );
    event RemoveRecipient( uint _index, address _recipient );
    
    /* ====== STRUCTS ====== */
    
    struct Info {
        uint rate; // in ten-thousandths ( 5000 = 0.5% )
        address recipient;
    }
    Info[] public info;
    
    struct Adjust {
        bool add;
        uint rate;
        uint target;
    }
    
    /* ======== INITIALIZATION ======== */

    function initialize( address _treasury, address _Vim, uint _epochLength, uint _nextEpochTimestamp ) external initializer {
        __Ownable_init();     
        require( _treasury != address(0) );
        treasury = _treasury;
        require( _Vim != address(0) );
        Vim = _Vim;
        epochLength = _epochLength;
        nextEpochTimestamp = (_nextEpochTimestamp == 0 ? block.timestamp + _epochLength : _nextEpochTimestamp);
    }
    
    /* ====== PUBLIC FUNCTIONS ====== */
    
    /**
        @notice send epoch reward to staking contract
     */
    function distribute() external returns ( bool ) {
        if ( nextEpochTimestamp <= block.timestamp ) {
            nextEpochTimestamp = nextEpochTimestamp.add( epochLength ); // set next epoch block
            
            // distribute rewards to each recipient
            for ( uint i = 0; i < info.length; i++ ) {
                if ( info[ i ].rate > 0 ) {
                    ITreasury( treasury ).mintRewards( // mint and send from treasury
                        info[ i ].recipient, 
                        nextRewardAt( info[ i ].rate ) 
                    );
                    adjust( i ); // check for adjustment
                }
            }
            return true;
        } else { 
            return false; 
        }
    }
    
    /* ====== INTERNAL FUNCTIONS ====== */

    /**
        @notice increment reward rate for collector
     */
    function adjust( uint _index ) internal {
        Adjust memory adjustment = adjustments[ _index ];
        if ( adjustment.rate != 0 ) {
            if ( adjustment.add ) { // if rate should increase
                info[ _index ].rate = info[ _index ].rate.add( adjustment.rate ); // raise rate
                if ( info[ _index ].rate >= adjustment.target ) { // if target met
                    adjustments[ _index ].rate = 0; // turn off adjustment
                }
            } else { // if rate should decrease
                info[ _index ].rate = info[ _index ].rate.sub( adjustment.rate ); // lower rate
                if ( info[ _index ].rate <= adjustment.target ) { // if target met
                    adjustments[ _index ].rate = 0; // turn off adjustment
                }
            }
        }
    }
    
    /* ====== VIEW FUNCTIONS ====== */

    /**
        @notice view function for next reward at given rate
        @param _rate uint
        @return uint
     */
    function nextRewardAt( uint _rate ) public view returns ( uint ) {
        return IERC20( Vim ).totalSupply().mul( _rate ).div( 1000000 );
    }

    /**
        @notice view function for next reward for specified address
        @param _recipient address
        @return uint
     */
    function nextRewardFor( address _recipient ) public view returns ( uint ) {
        uint reward;
        for ( uint i = 0; i < info.length; i++ ) {
            if ( info[ i ].recipient == _recipient ) {
                reward = nextRewardAt( info[ i ].rate );
            }
        }
        return reward;
    }
    
    /* ====== POLICY FUNCTIONS ====== */

    /**
        @notice adds recipient for distributions
        @param _recipient address
        @param _rewardRate uint
     */
    function addRecipient( address _recipient, uint _rewardRate ) external onlyOwner() {
        require( _recipient != address(0) );
        info.push( Info({
            recipient: _recipient,
            rate: _rewardRate
        }));
        emit AddRecipient(_recipient, _rewardRate);
    }

    /**
        @notice removes recipient for distributions
        @param _index uint
        @param _recipient address
     */
    function removeRecipient( uint _index, address _recipient ) external onlyOwner() {
        require( _recipient == info[ _index ].recipient );
        info[ _index ].recipient = address(0);
        info[ _index ].rate = 0;
        emit RemoveRecipient(_index, _recipient);
    }

    /**
        @notice set adjustment info for a collector's reward rate
        @param _index uint
        @param _add bool
        @param _rate uint
        @param _target uint
     */
    function setAdjustment( uint _index, bool _add, uint _rate, uint _target ) external onlyOwner() {
        require(_index < info.length, "Invalid index");
        adjustments[ _index ] = Adjust({
            add: _add,
            rate: _rate,
            target: _target
        });
        emit SetAdjustment(_index, _add, _rate, _target);
    }
}
