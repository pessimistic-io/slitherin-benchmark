/*
    

Telegram: https://t.me/QuantumProsperNetwork
Twitter: https://twitter.com/QuantumPN
*/

pragma solidity 0.8.19;

import "./Ownable.sol";
import "./IQPN.sol";
import "./IWETH.sol";
import "./IUniswapV2Router02.sol";

/// @title   QPNTreasury
/// @notice  QPN TREASURY
contract QPNTreasury is Ownable {
    /// STATE VARIABLS ///

    /// @notice Address of UniswapV2Router
    IUniswapV2Router02 public immutable uniswapV2Router;
    /// @notice QPN address
    address public immutable QPN;
    /// @notice WETH address
    address public immutable WETH;
    /// @notice QPN/ETH LP
    address public immutable uniswapV2Pair;

    /// @notice Distributor
    address public distributor;

    /// @notice 0.0001 ETHER
    uint256 public constant BACKING = 0.0001 ether;

    /// @notice Time to wait before removing liquidity again
    uint256 public constant TIME_TO_WAIT = 1 days;

    /// @notice Max percent of liqudity that can be removed at one time
    uint256 public constant MAX_REMOVAL = 10;

    /// @notice Timestamp of last liquidity removal
    uint256 public lastRemoval;

    /// CONSTRUCTOR ///

    /// @param _QPN  Address of QPN
    /// @param _WETH  Address of WETH
    constructor(address _QPN, address _WETH) {
        QPN = _QPN;
        WETH = _WETH;
        uniswapV2Pair = IQPN(QPN).uniswapV2Pair();

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        uniswapV2Router = _uniswapV2Router;
    }

    /// RECEIVE ///

    /// @notice Allow to receive ETH
    receive() external payable {}

    /// MINTER FUNCTION ///

    /// @notice         Distributor mints QPN
    /// @param _to      Address where to mint QPN
    /// @param _amount  Amount of QPN to mint
    function mintQPN(address _to, uint256 _amount) external {
        require(msg.sender == distributor, "msg.sender is not distributor");
        IQPN(QPN).mint(_to, _amount);
    }

    /// VIEW FUNCTION ///

    /// @notice         Returns amount of excess reserves
    /// @return value_  Excess reserves
    function excessReserves() external view returns (uint256 value_) {
        uint256 _balance = IERC20(WETH).balanceOf(address(this));
        uint256 _value = (_balance * 1e9) / BACKING;
        if (IERC20(QPN).totalSupply() > _value) return 0;
        return (_value - IERC20(QPN).totalSupply());
    }

    /// MUTATIVE FUNCTIONS ///

    /// @notice         Redeem QPN for backing
    /// @param _amount  Amount of QPN to redeem
    function redeemQPN(uint256 _amount) external {
        IQPN(QPN).burnFrom(msg.sender, _amount);
        IERC20(WETH).transfer(msg.sender, (_amount * BACKING) / 1e9);
    }

    /// @notice Wrap any ETH in conract
    function wrapETH() external {
        uint256 ethBalance_ = address(this).balance;
        if (ethBalance_ > 0) IWETH(WETH).deposit{value: ethBalance_}();
    }

    /// OWNER FUNCTIONS ///

    /// @notice              Set QPN distributor
    /// @param _distributor  Address of QPN distributor
    function setDistributor(address _distributor) external onlyOwner {
        require(distributor == address(0), "distributor already set");
        distributor = _distributor;
    }

    /// @notice         Remove liquidity and add to backing
    /// @param _amount  Amount of liquidity to remove
    function removeLiquidity(uint256 _amount) external onlyOwner {
        uint256 balance = IERC20(uniswapV2Pair).balanceOf(address(this));
        require(
            _amount <= (balance * MAX_REMOVAL) / 100,
            "Removing more than 10% of liquidity"
        );
        require(
            block.timestamp > lastRemoval + TIME_TO_WAIT,
            "Removed before 1 day lock"
        );
        lastRemoval = block.timestamp;

        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), _amount);

        uniswapV2Router.removeLiquidityETHSupportingFeeOnTransferTokens(
            QPN,
            _amount,
            0,
            0,
            address(this),
            block.timestamp
        );

        _burnQPN();
    }

    /// @notice         Withdraw stuck token from treasury
    /// @param _amount  Amount of token to remove
    /// @param _token   Address of token to remove
    function withdrawStuckToken(
        uint256 _amount,
        address _token
    ) external onlyOwner {
        require(_token != WETH, "Can not withdraw WETH");
        require(_token != uniswapV2Pair, "Can not withdraw LP");
        IERC20(_token).transfer(msg.sender, _amount);
    }

    /// INTERNAL FUNCTION ///

    /// @notice Burn QPN from Treasury to increase backing
    /// @dev    Invoked in `removeLiquidity()`
    function _burnQPN() internal {
        uint256 balance = IERC20(QPN).balanceOf(address(this));
        IQPN(QPN).burn(balance);
    }
}
