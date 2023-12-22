/*
        By Participating In 
       The Quantum Prosper Network 
     You Are Accelerating Your Wealth
With A Strong Network Of Beautiful Souls 

Telegram: https://t.me/QuantumProsperNetwork
Twitter: https://twitter.com/QuantumPN
*/

// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "./Ownable.sol";
import "./IERC20Metadata.sol";
import "./IsQPN.sol";
import "./IDistributor.sol";

/// @title   QPNStaking
/// @notice  QPN Staking
contract QPNStaking is Ownable {
    /// EVENTS ///

    event DistributorSet(address distributor);

    /// DATA STRUCTURES ///

    struct Epoch {
        uint256 length; // in seconds
        uint256 number; // since inception
        uint256 end; // timestamp
        uint256 distribute; // amount
    }

    /// STATE VARIABLES ///

    /// @notice QPN address
    IERC20 public immutable QPN;
    /// @notice sQPN address
    IsQPN public immutable sQPN;

    /// @notice Current epoch details
    Epoch public epoch;

    /// @notice Distributor address
    IDistributor public distributor;

    /// CONSTRUCTOR ///

    /// @param _QPN                   Address of QPN
    /// @param _sQPN                  Address of sQPN
    /// @param _epochLength            Epoch length
    /// @param _secondsTillFirstEpoch  Seconds till first epoch starts
    constructor(
        address _QPN,
        address _sQPN,
        uint256 _epochLength,
        uint256 _secondsTillFirstEpoch
    ) {
        require(_QPN != address(0), "Zero address: QPN");
        QPN = IERC20(_QPN);
        require(_sQPN != address(0), "Zero address: sQPN");
        sQPN = IsQPN(_sQPN);

        epoch = Epoch({
            length: _epochLength,
            number: 0,
            end: block.timestamp + _secondsTillFirstEpoch,
            distribute: 0
        });
    }

    /// MUTATIVE FUNCTIONS ///

    /// @notice stake QPN
    /// @param _to address
    /// @param _amount uint
    function stake(address _to, uint256 _amount) external {
        rebase();
        QPN.transferFrom(msg.sender, address(this), _amount);
        sQPN.transfer(_to, _amount);
    }


    /// @notice redeem sQPN for QPN
    /// @param _to address
    /// @param _amount uint
    function unstake(address _to, uint256 _amount, bool _rebase) external {
        if (_rebase) rebase();
        sQPN.transferFrom(msg.sender, address(this), _amount);
        require(
            _amount <= QPN.balanceOf(address(this)),
            "Insufficient QPN balance in contract"
        );
        QPN.transfer(_to, _amount);
    }

    ///@notice Trigger rebase if epoch over
    function rebase() public {
        if (epoch.end <= block.timestamp) {
            sQPN.rebase(epoch.distribute, epoch.number);

            epoch.end = epoch.end + epoch.length;
            epoch.number++;

            if (address(distributor) != address(0)) {
                distributor.distribute();
            }

            uint256 balance = QPN.balanceOf(address(this));
            uint256 staked = sQPN.circulatingSupply();

            if (balance <= staked) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = balance - staked;
            }
        }
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice         Send sQPN upon staking
    /// @param _to      Address of where sending sQPN
    /// @param _amount  Amount of sQPN to send
    /// @return _sent   Amount of sQPN sent
    function _send(
        address _to,
        uint256 _amount
    ) internal returns (uint256 _sent) {
        sQPN.transfer(_to, _amount); // send as sQPN (equal unit as QPN)
        return _amount;
    }

    /// VIEW FUNCTIONS ///

    /// @notice         Returns the sQPN index, which tracks rebase growth
    /// @return index_  Index of sQPN
    function index() public view returns (uint256 index_) {
        return sQPN.index();
    }

    /// @notice           Returns econds until the next epoch begins
    /// @return seconds_  Till next epoch
    function secondsToNextEpoch() external view returns (uint256 seconds_) {
        return epoch.end - block.timestamp;
    }

    /// MANAGERIAL FUNCTIONS ///

    /// @notice              Sets the contract address for LP staking
    /// @param _distributor  Distributor Address
    function setDistributor(address _distributor) external onlyOwner {
        distributor = IDistributor(_distributor);
        emit DistributorSet(_distributor);
    }
}
