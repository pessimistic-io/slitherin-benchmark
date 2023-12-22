pragma solidity 0.8.17;

import "./IRegistry.sol";
import "./IMarket.sol";
import "./IParameters.sol";

contract PolicyUnlocker {
    uint256 public maxGasPrice = 30 gwei;
    IRegistry immutable registry;
    IParameters immutable param;

    constructor(address _registry, address _parameter) {
        registry = IRegistry(_registry);
        param = IParameters(_parameter);
    }

    function unlockBatch(address _targetMarket, uint256[] memory _ids)
        external
    {
        IMarket _market = IMarket(_targetMarket);

        _market.unlockBatch(_ids);
    }

    function checker()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        if (tx.gasprice <= maxGasPrice) {
            (
                address _market,
                uint256[] memory _ids
            ) = _getFirstUnlockablePoolAndIds();

            if (_ids.length != 0) {
                canExec = true;

                execPayload = abi.encodeWithSelector(
                    this.unlockBatch.selector,
                    address(_market),
                    _ids
                );
            } else {
                execPayload = bytes("No Unlockable Policy");
            }
        }
    }

    function manualExecute() external {
        (
            address _market,
            uint256[] memory _ids
        ) = _getFirstUnlockablePoolAndIds();

        if (_ids.length != 0) {
            IMarket(_market).unlockBatch(_ids);
        }
    }

    function _getFirstUnlockablePoolAndIds()
        internal
        view
        returns (address, uint256[] memory)
    {
        address[] memory _markets = _getAllMarkets();
        IMarket _market;
        uint256[] memory _ids;

        for (uint256 i; i < _markets.length; ) {
            _market = IMarket(_markets[i]);
            _ids = _getAllUnlockableIds(_market);

            if (_ids.length != 0) {
                break;
            }

            unchecked {
                ++i;
            }
        }

        return (address(_market), _ids);
    }

    function _getAllMarkets() internal view returns (address[] memory) {
        return registry.getAllMarkets();
    }

    function _getAllUnlockableIds(IMarket _market)
        internal
        view
        returns (uint256[] memory)
    {
        if (
            _isMarket(_market) &&
            _market.marketStatus() == IMarket.MarketStatus.Trading
        ) {
            uint256 _idCounts = _market.allInsuranceCount();
            uint256 _gracePeriod = param.getGrace(address(_market));

            uint256[] memory _draftUnlockableIds = new uint256[](_idCounts);
            uint256 _nextSlot;

            for (uint256 i; i < _idCounts; ) {
                IMarket.Insurance memory _insurance = _market.insurances(i);
                uint256 _unlockableTime = uint256(_insurance.endTime) +
                    _gracePeriod;

                if (_insurance.status && _unlockableTime <= block.timestamp) {
                    _draftUnlockableIds[_nextSlot] = i;
                    ++_nextSlot;
                }

                unchecked {
                    ++i;
                }
            }

            uint256[] memory _unlockableIds = new uint256[](_nextSlot);

            for (uint256 i; i < _nextSlot; i++) {
                _unlockableIds[i] = _draftUnlockableIds[i];
            }

            return _unlockableIds;
        }
    }

    function _isMarket(IMarket _market) internal view returns (bool) {
        try _market.marketStatus() returns (IMarket.MarketStatus) {
            return true;
        } catch {}
    }

    function setMaxGasPrice(uint256 _gwei) external {
        maxGasPrice = _gwei * 1 gwei;
    }

    //fnctions for test
    function getFirstUnlockablePoolAndIds()
        external
        view
        returns (address, uint256[] memory)
    {
        return _getFirstUnlockablePoolAndIds();
    }

    function getAllMarkets() external view returns (address[] memory) {
        return _getAllMarkets();
    }

    function getAllUnlockableIds(IMarket _market)
        external
        view
        returns (uint256[] memory _unlockableIds)
    {
        return _getAllUnlockableIds(_market);
    }
}

