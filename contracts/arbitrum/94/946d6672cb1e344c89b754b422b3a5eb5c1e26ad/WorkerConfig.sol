// SPDX-License-Identifier: MIT
/**
  ∩~~~~∩
  ξ ･×･ ξ
  ξ　~　ξ
  ξ　　 ξ
  ξ　　 “~～~～〇
  ξ　　　　　　 ξ
  ξ ξ ξ~～~ξ ξ ξ
　 ξ_ξξ_ξ　ξ_ξξ_ξ
Alpaca Fin Corporation
*/

pragma solidity 0.6.6;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./Initializable.sol";
import "./ERC20.sol";

import "./IWorker.sol";
import "./IWorkerConfig.sol";
import "./IPriceOracle.sol";
import "./INFTBoostedLeverageController.sol";
import "./SafeToken.sol";

contract WorkerConfig is OwnableUpgradeSafe, IWorkerConfig {
    /// @notice Using libraries
    using SafeToken for address;
    using SafeMath for uint256;

    /// @notice Events
    event SetOracle(address indexed caller, address oracle);
    event SetConfig(
        address indexed caller,
        address indexed worker,
        bool acceptDebt,
        uint64 workFactor,
        uint64 killFactor,
        uint64 maxPriceDiff
    );
    event SetGovernor(address indexed caller, address indexed governor);
    event LogSetNFTBoostedLeverageController(
        address oldAddress,
        address newAddress,
        address caller
    );

    /// @notice state variables
    struct Config {
        bool acceptDebt;
        uint64 workFactor;
        uint64 killFactor;
        uint64 maxPriceDiff;
    }

    PriceOracle public oracle;
    mapping(address => Config) public workers;
    address public governor;
    INFTBoostedLeverageController public nftBoostedLeverageController;

    function initialize(PriceOracle _oracle) external initializer {
        OwnableUpgradeSafe.__Ownable_init();
        oracle = _oracle;
    }

    /// @dev Check if the msg.sender is the governor.
    modifier onlyGovernor() {
        require(
            msg.sender == governor,
            "WorkerConfig::onlyGovernor:: msg.sender not governor"
        );
        _;
    }

    /// @dev Set oracle address. Must be called by owner.
    function setOracle(PriceOracle _oracle) external onlyOwner {
        oracle = _oracle;
        emit SetOracle(msg.sender, address(oracle));
    }

    /// @dev Set worker configurations. Must be called by owner.
    function setConfigs(
        address[] calldata addrs,
        Config[] calldata configs
    ) external onlyOwner {
        uint256 len = addrs.length;
        require(configs.length == len, "WorkConfig::setConfigs:: bad len");
        for (uint256 idx = 0; idx < len; idx++) {
            workers[addrs[idx]] = Config({
                acceptDebt: configs[idx].acceptDebt,
                workFactor: configs[idx].workFactor,
                killFactor: configs[idx].killFactor,
                maxPriceDiff: configs[idx].maxPriceDiff
            });
            emit SetConfig(
                msg.sender,
                addrs[idx],
                workers[addrs[idx]].acceptDebt,
                workers[addrs[idx]].workFactor,
                workers[addrs[idx]].killFactor,
                workers[addrs[idx]].maxPriceDiff
            );
        }
    }

    function isReserveConsistent(
        address worker
    ) public view override returns (bool) {
        IPancakePair lp = IWorker(worker).lpToken();
        address token0 = lp.token0();
        address token1 = lp.token1();
        (uint256 r0, uint256 r1, ) = lp.getReserves();
        uint256 t0bal = token0.balanceOf(address(lp));
        uint256 t1bal = token1.balanceOf(address(lp));
        _isReserveConsistent(r0, r1, t0bal, t1bal);
        return true;
    }

    function _isReserveConsistent(
        uint256 r0,
        uint256 r1,
        uint256 t0bal,
        uint256 t1bal
    ) internal pure {
        require(
            t0bal.mul(100) <= r0.mul(101),
            "WorkerConfig::isReserveConsistent:: bad t0 balance"
        );
        require(
            t1bal.mul(100) <= r1.mul(101),
            "WorkerConfig::isReserveConsistent:: bad t1 balance"
        );
    }

    /// @dev Return whether the given worker is stable, presumably not under manipulation.
    function isStable(address worker) public view override returns (bool) {
        IPancakePair lp = IWorker(worker).lpToken();
        ERC20UpgradeSafe token0 = ERC20UpgradeSafe(lp.token0());
        ERC20UpgradeSafe token1 = ERC20UpgradeSafe(lp.token1());
        // 1. Check that reserves and balances are consistent (within 1%)
        (uint256 r0, uint256 r1, ) = lp.getReserves();
        uint256 t0bal = token0.balanceOf(address(lp));
        uint256 t1bal = token1.balanceOf(address(lp));
        _isReserveConsistent(r0, r1, t0bal, t1bal);
        // 2. Check that price is in the acceptable range
        (uint256 price, uint256 lastUpdate) = oracle.getPrice(
            address(token0),
            address(token1)
        );
        require(
            lastUpdate >= now - 1 days,
            "WorkerConfig::isStable:: price too stale"
        );
        uint256 lpPrice = r1
            .mul(1e18)
            .mul(10 ** (18 - uint256(token1.decimals())))
            .div(r0)
            .div(10 ** (18 - uint256(token0.decimals())));
        uint256 maxPriceDiff = workers[worker].maxPriceDiff;
        require(
            lpPrice.mul(10000) <= price.mul(maxPriceDiff),
            "WorkerConfig::isStable:: price too high"
        );
        require(
            lpPrice.mul(maxPriceDiff) >= price.mul(10000),
            "WorkerConfig::isStable:: price too low"
        );
        // 3. Done
        return true;
    }

    /// @dev Return whether the given worker accepts more debt.
    function acceptDebt(address worker) external view override returns (bool) {
        require(isStable(worker), "WorkerConfig::acceptDebt:: !stable");
        return workers[worker].acceptDebt;
    }

    /// @dev Return the work factor for the worker + BaseToken debt, using 1e4 as denom.
    function workFactor(
        address worker,
        uint256 /* debt */
    ) external view override returns (uint256) {
        require(isStable(worker), "WorkerConfig::workFactor:: !stable");
        return uint256(workers[worker].workFactor);
    }

    /// @dev Return the work factor for the worker + BaseToken debt, using 1e4 as denom.
    /// Also check for boosted leverage from NFT staking
    function workFactor(
        address worker,
        uint256 /* debt */,
        address positionOwner
    ) external view override returns (uint256) {
        require(isStable(worker), "WorkerConfig::workFactor:: !stable");
        if (address(nftBoostedLeverageController) == address(0))
            return uint256(workers[worker].workFactor);
        uint256 _boostedWorkFactor = nftBoostedLeverageController
            .getBoostedWorkFactor(positionOwner, worker);
        return
            _boostedWorkFactor > 0
                ? _boostedWorkFactor
                : uint256(workers[worker].workFactor);
    }

    /// @dev Return the kill factor for the worker + BaseToken debt, using 1e4 as denom.
    function killFactor(
        address worker,
        uint256 /* debt */
    ) external view override returns (uint256) {
        require(isStable(worker), "WorkerConfig::killFactor:: !stable");
        return uint256(workers[worker].killFactor);
    }

    function killFactor(
        address worker,
        uint256 /* debt */,
        address positionOwner
    ) external view override returns (uint256) {
        require(isStable(worker), "WorkerConfig::killFactor:: !stable");
        if (address(nftBoostedLeverageController) == address(0))
            return uint256(workers[worker].killFactor);
        uint256 _boostedKillFactor = nftBoostedLeverageController
            .getBoostedKillFactor(positionOwner, worker);
        return
            _boostedKillFactor > 0
                ? _boostedKillFactor
                : uint256(workers[worker].killFactor);
    }

    /// @dev Return the kill factor for the worker + BaseToken debt, using 1e4 as denom.
    function rawKillFactor(
        address worker,
        uint256 /* debt */
    ) external view override returns (uint256) {
        return uint256(workers[worker].killFactor);
    }

    function rawKillFactor(
        address worker,
        uint256 /* debt */,
        address positionOwner
    ) external view override returns (uint256) {
        if (address(nftBoostedLeverageController) == address(0))
            return uint256(workers[worker].killFactor);
        uint256 _boostedKillFactor = nftBoostedLeverageController
            .getBoostedKillFactor(positionOwner, worker);
        return
            _boostedKillFactor > 0
                ? _boostedKillFactor
                : uint256(workers[worker].killFactor);
    }

    /// @dev Set governor address. OnlyOwner can set governor.
    function setGovernor(address newGovernor) external onlyOwner {
        governor = newGovernor;
        emit SetGovernor(msg.sender, governor);
    }

    /// @dev EMERGENCY ONLY. Disable accept new position without going through Timelock in case of emergency.
    function emergencySetAcceptDebt(
        address[] calldata addrs,
        bool isAcceptDebt
    ) external onlyGovernor {
        uint256 len = addrs.length;
        for (uint256 idx = 0; idx < len; idx++) {
            workers[addrs[idx]].acceptDebt = isAcceptDebt;
            emit SetConfig(
                msg.sender,
                addrs[idx],
                workers[addrs[idx]].acceptDebt,
                workers[addrs[idx]].workFactor,
                workers[addrs[idx]].killFactor,
                workers[addrs[idx]].maxPriceDiff
            );
        }
    }

    function setNFTBoostedLeverageController(
        INFTBoostedLeverageController _newNFTBoostedLeverageController
    ) external onlyOwner {
        // Sanity check
        _newNFTBoostedLeverageController.getBoostedWorkFactor(
            address(0),
            address(0)
        );
        INFTBoostedLeverageController oldNFTBoostedLeverageController = nftBoostedLeverageController;
        nftBoostedLeverageController = _newNFTBoostedLeverageController;

        emit LogSetNFTBoostedLeverageController(
            address(oldNFTBoostedLeverageController),
            address(_newNFTBoostedLeverageController),
            msg.sender
        );
    }
}

