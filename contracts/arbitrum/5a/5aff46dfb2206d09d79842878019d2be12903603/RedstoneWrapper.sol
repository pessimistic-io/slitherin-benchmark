// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.13;

import "./PrimaryProdDataServiceConsumerBase.sol";
import "./OwnableUpgradeable.sol";
import "./BaseWrapper.sol";

contract RedstoneWrapper is PrimaryProdDataServiceConsumerBase, BaseWrapper, OwnableUpgradeable {
    event OracleAdded(address indexed _token, address _externalOracle);

    struct OracleResponse {
        uint256 currentPrice;
        uint256 lastPrice;
        uint256 lastUpdate;
        bool success;
    }

    struct Oracle {
        bytes32 code;
        uint8 decimals;
    }

    mapping(address => Oracle) public oracles;
    mapping(address => SavedResponse) public savedResponses;

    function setUp() external initializer {
        __Ownable_init();
    }

    function addOracle(address _token, bytes32 _code, uint8 _decimals) external onlyOwner {
        require(_decimals != 0, "Invalid Decimals");

        oracles[_token] = Oracle(_code, _decimals);

        OracleResponse memory response = _getResponses(_token);

        if (_isBadOracleResponse(response)) {
            revert ResponseFromOracleIsInvalid(_token, address(this));
        }

        savedResponses[_token].currentPrice = response.currentPrice;
        savedResponses[_token].lastPrice = response.lastPrice;
        savedResponses[_token].lastUpdate = response.lastUpdate;

        emit OracleAdded(_token, address(this));
    }

    function removeOracle(address _token) external onlyOwner {
        delete oracles[_token];
        delete savedResponses[_token];
    }

    function retriveSavedResponses(address _token) external override returns (SavedResponse memory savedResponse) {
        fetchPrice(_token);
        return savedResponses[_token];
    }

    function fetchPrice(address _token) public override {
        OracleResponse memory oracleResponse = _getResponses(_token);
        SavedResponse storage responses = savedResponses[_token];

        if (_isBadOracleResponse(oracleResponse)) return;

        responses.currentPrice = oracleResponse.currentPrice;
        responses.lastPrice = oracleResponse.lastPrice;
        responses.lastUpdate = oracleResponse.lastUpdate;
    }

    function getLastPrice(address _token) external view override returns (uint256) {
        return savedResponses[_token].lastPrice;
    }

    function getCurrentPrice(address _token) external view override returns (uint256) {
        return savedResponses[_token].currentPrice;
    }

    function getExternalPrice(address _token) external view override returns (uint256) {
        OracleResponse memory oracleResponse = _getResponses(_token);
        return oracleResponse.currentPrice;
    }

    function _getResponses(address _token) internal view returns (OracleResponse memory response) {
        Oracle memory oracle = oracles[_token];
        if (oracle.code == bytes32(0)) {
            revert TokenIsNotRegistered(_token);
        }

        uint8 decimals = oracle.decimals;
        uint256 currentPrice = getOracleNumericValueFromTxMsg(oracle.code);
        uint256 scaledPrice = scalePriceByDigits(currentPrice, decimals);

        response.lastUpdate = block.timestamp;
        response.currentPrice = scaledPrice;
        response.lastPrice = scaledPrice;
        response.success = currentPrice != 0;

        return response;
    }

    function _isBadOracleResponse(OracleResponse memory _response) internal pure returns (bool) {
        return (!_response.success || _response.currentPrice <= 0);
    }
}

