//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Types.sol";

interface IVault {
    /*==================== Operational Functions *====================*/

    function depositReservedAmount(
        address _token,
        address _sender,
        uint256 _sentAmount,
        uint256 _autoRollAmount,
        uint256 _gameId,
        uint256 _toReserve
    ) external;

    function withdrawReservedAmount(
        address _token,
        uint256 _amount,
        uint256 _toReserve,
        address _address
    ) external;

    function predictFees(uint256 _gameId) external returns (uint256 gameFee_);

    function addFees(
        address _token,
        address _frontendReferral,
        address _gameProvider,
        uint256 _sentValue,
        uint256 _gameId
    ) external;

    function refund(
        address _token,
        uint256 _amount,
        uint256 _toReserve,
        address _player,
        uint256 _gameId
    ) external;

    function directPoolDeposit(
        address _address,
        address _token,
        uint256 _amount
    ) external;

    function withdrawFeeCollector(address _token, uint256 _amount) external;

    function editWhitelistedTokens(address _token, bool _value) external;

    function editAddresses(
        address _paraliqAddress,
        address _azuroLiquidityAddress
    ) external;

    function withdrawReservedAmountGovernance(
        address _game,
        address _token,
        uint256 _amount
    ) external;

    function setMinWager(
        address _game,
        address _token,
        uint256 _minWager
    ) external;

    function editGameVault(
        address _game,
        bool _isPresent,
        Types.GameFee memory _transactionFee
    ) external;

    function editExtraEdgeFee(address _user, uint256 _value) external;

    function calculateGameFee(address _game) external returns (uint256);

    /*==================== View Functions *====================*/

    function getWhitelistedToken(address _token) external view returns (bool);

    function getGameVault(
        address _game
    ) external view returns (Types.GameVaultReturn memory);

    function getReservedAmount(
        address _game,
        address _token
    ) external view returns (Types.ReservedAmount memory);

    function getReserveLimit(
        address _game,
        address _token
    ) external view returns (uint256 reserveLimit_);

    function getMaxPayout(
        address _game,
        address _token
    ) external view returns (uint256 maxWager_);

    function getMinWager(
        address _game,
        address _token
    ) external view returns (uint256);
}

