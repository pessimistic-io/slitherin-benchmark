// SPDX-License-Identifier: MIT
// Credits: TreasureDAO MasterOfCoin
pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ITreasury.sol";
import "./TreasuryBase.sol";

contract Treasury is ITreasury, AccessControlEnumerableUpgradeable, TreasuryBase {
  using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
  using SafeERC20Upgradeable for IERC20Upgradeable;

  EnumerableSetUpgradeable.AddressSet private streams;

  modifier streamExists(address _stream) {
    require(streams.contains(_stream), "Stream does not exist");
    _;
  }

  modifier streamActive(address _stream) {
    require(streamInfo[_stream].endTimestamp > block.timestamp, "Stream ended");
    _;
  }

  function initialize(address _boo, address _admin) public initializer {
    boo = IERC20Upgradeable(_boo);
    _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    _grantRole(ADMIN_ROLE, _admin);

    __AccessControlEnumerable_init();
  }

  function requestFund() public virtual returns (uint256 fundedAmount) {
    StreamInfo storage stream = streamInfo[msg.sender];

    fundedAmount = getPendingFund(msg.sender);

    if (fundedAmount == 0 || boo.balanceOf(address(this)) < fundedAmount) {
      return 0;
    }

    stream.lastPullTimestamp = block.timestamp;
    stream.funded += fundedAmount;

    require(stream.funded <= stream.totalFund, "Rewards overflow");

    boo.safeTransfer(msg.sender, fundedAmount);
    emit StreamFunded(msg.sender, fundedAmount, stream.funded);
  }

  function getPendingFund(address _stream) public view returns (uint256 pendingFund) {
    StreamInfo storage stream = streamInfo[_stream];

    if (block.timestamp >= stream.endTimestamp) {
      pendingFund  = stream.totalFund - stream.funded;
    } else if (block.timestamp > stream.lastPullTimestamp) {
      pendingFund = (stream.ratePerSecond * (block.timestamp - stream.lastPullTimestamp));
      if (pendingFund + stream.funded > stream.totalFund) {
        pendingFund = stream.totalFund - stream.funded;
      }
    }
  }

  function getStreams() external view virtual returns (address[] memory) {
        return streams.values();
    }

  function getStreamInfo(address _stream) external view virtual returns (StreamInfo memory) {
      return streamInfo[_stream];
  }

  function getGlobalRatePerSecond() external view virtual returns (uint256 globalRatePerSecond) {
      uint256 len = streams.length();
      for (uint256 i = 0; i < len; i++) {
          globalRatePerSecond += getRatePerSecond(streams.at(i));
      }
  }

    function getRatePerSecond(address _stream) public view virtual returns (uint256 ratePerSecond) {
        StreamInfo storage stream = streamInfo[_stream];

        if (stream.startTimestamp < block.timestamp && block.timestamp < stream.endTimestamp) {
            ratePerSecond = stream.ratePerSecond;
        }
    }


  function grantTokenToStream(address _stream, uint256 _amount)
        public
        virtual
        streamExists(_stream)
        streamActive(_stream)
    {
        _fundStream(_stream, _amount);

        boo.safeTransferFrom(msg.sender, address(this), _amount);
        emit StreamGrant(_stream, msg.sender, _amount);
    }

  function addFund(address _stream, uint256 _amount)
        external
        virtual
        onlyRole(ADMIN_ROLE)
        streamExists(_stream)
        streamActive(_stream)
  {
      _fundStream(_stream, _amount);
      emit FundAdded(_stream, _amount);
  }

  function removeFund(address _stream, uint256 _amount)
        external
        virtual
        onlyRole(ADMIN_ROLE)
        streamExists(_stream)
        streamActive(_stream)
    {
        StreamInfo storage stream = streamInfo[_stream];

        uint256 secondsToEnd = stream.endTimestamp - stream.lastPullTimestamp;
        uint256 rewardsLeft = secondsToEnd * stream.ratePerSecond;

        require(_amount <= rewardsLeft, "Reduce amount too large, rewards already paid");

        stream.ratePerSecond = (rewardsLeft - _amount) / secondsToEnd;
        stream.totalFund -= _amount;

        emit StreamDefunded(_stream, _amount);
    }

  function addStream(
    address _stream,
    uint256 _totalFund,
    uint256 _startTimestamp,
    uint256 _endTimestamp
  ) external onlyRole(ADMIN_ROLE) {
    require(_endTimestamp > _startTimestamp, "Rewards must last > 1 sec");
    require(!streams.contains(_stream), "Stream already exists");

    if (streams.add(_stream)) {
      streamInfo[_stream] = StreamInfo({
        totalFund: _totalFund,
        startTimestamp: _startTimestamp,
        endTimestamp: _endTimestamp,
        lastPullTimestamp: _startTimestamp,
        ratePerSecond: _totalFund / (_endTimestamp - _startTimestamp),
        funded: 0
      });
      emit StreamAdded(_stream, _totalFund, _startTimestamp, _endTimestamp);
    }
  }

  function _fundStream(address _stream, uint256 _amount) internal virtual {
    StreamInfo storage stream = streamInfo[_stream];

    uint256 secondsToEnd = stream.endTimestamp - stream.lastPullTimestamp;
    uint256 fundLeft = secondsToEnd * stream.ratePerSecond;
    stream.ratePerSecond = (fundLeft + _amount) / secondsToEnd;
    stream.totalFund += _amount;
  }

  function updateStreamTime(address _stream, uint256 _startTimestamp, uint256 _endTimestamp)
        external
        virtual
        onlyRole(ADMIN_ROLE)
        streamExists(_stream)
    {
        StreamInfo storage stream = streamInfo[_stream];

        if (_startTimestamp > 0) {
            require(_startTimestamp > block.timestamp, "startTimestamp cannot be in the past");

            stream.startTimestamp = _startTimestamp;
            stream.lastPullTimestamp = _startTimestamp;
        }

        if (_endTimestamp > 0) {
            require(_endTimestamp > _startTimestamp, "Rewards must last > 1 sec");
            require(_endTimestamp > block.timestamp, "Cannot end rewards in the past");

            stream.endTimestamp = _endTimestamp;
        }

        stream.ratePerSecond = (stream.totalFund - stream.funded) / (stream.endTimestamp - stream.lastPullTimestamp);

        emit StreamTimeUpdated(_stream, _startTimestamp, _endTimestamp);
    }

    function removeStream(address _stream)
        external
        virtual
        onlyRole(ADMIN_ROLE)
        streamExists(_stream)
    {
        if (streams.remove(_stream)) {
            delete streamInfo[_stream];
            emit StreamRemoved(_stream);
        }
    }


  function withdrawBOO(address _to, uint256 _amount) external virtual onlyRole(ADMIN_ROLE) {
        boo.safeTransfer(_to, _amount);
        emit Withdraw(_to, _amount);
    }

  function setBOO(address _boo) external virtual onlyRole(ADMIN_ROLE) {
      boo = IERC20Upgradeable(_boo);
  }
}
