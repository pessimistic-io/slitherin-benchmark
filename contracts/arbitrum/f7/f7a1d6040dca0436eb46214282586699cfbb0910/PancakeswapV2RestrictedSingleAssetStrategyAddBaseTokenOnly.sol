// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.6.6;

import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./Initializable.sol";
import "./Ownable.sol";

import "./IPancakeFactory.sol";
import "./IPancakePair.sol";

import "./IPancakeRouter02.sol";
import "./IStrategy.sol";
import "./SafeToken.sol";
import "./OpenMath.sol";
import "./IWorker02.sol";

contract PancakeswapV2RestrictedSingleAssetStrategyAddBaseTokenOnly is
    OwnableUpgradeSafe,
    ReentrancyGuardUpgradeSafe,
    IStrategy
{
    using SafeToken for address;
    using SafeMath for uint256;

    IPancakeFactory public factory;
    IPancakeRouter02 public router;
    address public wNative;
    mapping(address => bool) public okWorkers;

    /// @notice require that only allowed workers are able to do the rest of the method call
    modifier onlyWhitelistedWorkers() {
        require(
            okWorkers[msg.sender],
            "PancakeswapV2RestrictedSingleAssetStrategyAddBaseTokenOnly::onlyWhitelistedWorkers:: bad worker"
        );
        _;
    }

    /// @dev Create a new add Token only strategy instance.
    /// @param _router The Pancakeswap router smart contract.
    function initialize(IPancakeRouter02 _router) external initializer {
        OwnableUpgradeSafe.__Ownable_init();
        ReentrancyGuardUpgradeSafe.__ReentrancyGuard_init();
        factory = IPancakeFactory(_router.factory());
        router = _router;
        wNative = _router.WETH();
    }

    /// @dev Execute worker strategy. Take BaseToken. Return Farming tokens.
    /// @param data Extra calldata information passed along to this strategy.
    function execute(
        address /* user */,
        uint256 /* debt */,
        bytes calldata data
    ) external override onlyWhitelistedWorkers nonReentrant {
        // 1. Find out what farming token we are dealing with and min additional LP tokens.
        uint256 minLPAmount = abi.decode(data, (uint256));
        IWorker worker = IWorker(msg.sender);
        address baseToken = worker.baseToken();
        address farmingToken = worker.farmingToken();
        IPancakePair lpToken = IPancakePair(
            factory.getPair(farmingToken, baseToken)
        );
        // 2. Approve router to do their stuffs
        baseToken.safeApprove(address(router), uint256(-1));
        farmingToken.safeApprove(address(router), uint256(-1));
        // 3. Compute the optimal amount of baseToken to be converted to farmingToken.
        uint256 balance = baseToken.myBalance();
        (uint256 r0, uint256 r1, ) = lpToken.getReserves();
        uint256 rIn = lpToken.token0() == baseToken ? r0 : r1;
        // find how many baseToken need to be converted to farmingToken
        // Constants come from
        // 2-f = 2-0.0025 = 19975
        // 4(1-f) = 4*9975*10000 = 399000000, where f = 0.0025 and 10,000 is a way to avoid floating point
        // 19975^2 = 399000625
        // 9975*2 = 19950
        uint256 aIn = OpenMath
            .sqrt(rIn.mul(balance.mul(399000000).add(rIn.mul(399000625))))
            .sub(rIn.mul(19975)) / 19950;
        // 4. Convert that portion of baseToken to farmingToken.
        address[] memory path = new address[](2);
        path[0] = baseToken;
        path[1] = farmingToken;
        router.swapExactTokensForTokens(aIn, 0, path, address(this), now);
        // 5. Mint more LP tokens and return all LP tokens to the sender.
        (, , uint256 moreLPAmount) = router.addLiquidity(
            baseToken,
            farmingToken,
            baseToken.myBalance(),
            farmingToken.myBalance(),
            0,
            0,
            address(this),
            now
        );
        require(
            moreLPAmount >= minLPAmount,
            "PancakeswapV2RestrictedStrategyAddBaseTokenOnly::execute:: insufficient LP tokens received"
        );
        require(
            lpToken.transfer(msg.sender, lpToken.balanceOf(address(this))),
            "PancakeswapV2RestrictedStrategyAddBaseTokenOnly::execute:: failed to transfer LP token to msg.sender"
        );
        // 6. Reset approval for safety reason
        baseToken.safeApprove(address(router), 0);
        farmingToken.safeApprove(address(router), 0);
    }

    function setWorkersOk(
        address[] calldata workers,
        bool isOk
    ) external onlyOwner {
        for (uint256 idx = 0; idx < workers.length; idx++) {
            okWorkers[workers[idx]] = isOk;
        }
    }
}

