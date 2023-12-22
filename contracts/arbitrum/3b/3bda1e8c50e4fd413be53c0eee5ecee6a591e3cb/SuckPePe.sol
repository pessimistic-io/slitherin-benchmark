pragma solidity 0.8.19;

import "./ERC20.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./ICamelotFactory.sol";
import "./ICamelotRouter.sol";
import "./IWETH.sol";

contract SuckPePe is ERC20, Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    event SwapBack(uint256 burn, uint256 treasury, uint256 timestamp);
    event Trade(
        address user,
        address pair,
        uint256 amount,
        uint256 side,
        uint256 circulatingSupply,
        uint256 timestamp
    );

    bool public swapEnabled = true;

    bool public inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    mapping(address => bool) public isFeeExempt;

    uint256 public feeDenominator = 10000;

    // Sell Fees
    uint256 public burnFee = 900;
    uint256 public treasuryFee = 600;
    uint256 public totalFee = 1500;

    // Fees receivers
    address private treasuryWallet;

    IERC20 public backToken;
    ICamelotFactory private immutable factory;
    ICamelotRouter private immutable swapRouter;
    IWETH private immutable WETH;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address private constant ZERO = 0x0000000000000000000000000000000000000000;

    EnumerableSet.AddressSet private _pairs;

    constructor(
        IERC20 _backToken,
        address _factory,
        address _swapRouter,
        address _weth,
        address _treasuryWallet,
        address _receiveTokenWallet
    ) ERC20("SuckPEPE", "SPE") {
        uint256 _totalSupply = 1_000_000_000_000_000_000 * 1e6;
        backToken = _backToken;
        treasuryWallet = _treasuryWallet;
        isFeeExempt[_treasuryWallet] = true;
        isFeeExempt[_receiveTokenWallet] = true;
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        factory = ICamelotFactory(_factory);
        swapRouter = ICamelotRouter(_swapRouter);
        WETH = IWETH(_weth);
        _mint(_receiveTokenWallet, _totalSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function transfer(address to, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        return _suckTransfer(_msgSender(), to, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return _suckTransfer(sender, recipient, amount);
    }

    function _suckTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if (inSwap) {
            _transfer(sender, recipient, amount);
            return true;
        }

        bool shouldTakeFee = !isFeeExempt[sender] && !isFeeExempt[recipient];
        uint256 side = 0;
        address user_ = sender;
        address pair_ = recipient;
        // Set Fees
        if (isPair(sender)) {
            //Buy
            side = 1;
            user_ = recipient;
            pair_ = sender;
            shouldTakeFee = false;
        } else if (isPair(recipient)) {
            //Sell
            side = 2;
        } else {
            shouldTakeFee = false;
        }

        if (shouldSwapBack()) {
            swapBack();
        }

        uint256 amountReceived = shouldTakeFee
            ? takeFee(sender, amount)
            : amount;
        _transfer(sender, recipient, amountReceived);

        if (side > 0) {
            emit Trade(
                user_,
                pair_,
                amount,
                side,
                getCirculatingSupply(),
                block.timestamp
            );
        }
        return true;
    }

    function shouldSwapBack() internal view returns (bool) {
        return
            !inSwap &&
            swapEnabled &&
            balanceOf(address(this)) > 0 &&
            !isPair(_msgSender());
    }

    function swapBack() internal swapping {
        uint256 taxAmount = balanceOf(address(this));
        _approve(address(this), address(swapRouter), taxAmount);

        uint256 amountSuckBurn = (taxAmount * burnFee) / (totalFee);
        taxAmount -= amountSuckBurn;

        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = address(WETH);
        path[2] = address(backToken);

        bool success = false;
        uint256 balanceBefore = backToken.balanceOf(address(this));
        try
            swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                taxAmount,
                0,
                path,
                address(this),
                address(0),
                block.timestamp
            )
        {
            success = true;
        } catch {
            try
                swapRouter
                    .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        taxAmount,
                        0,
                        path,
                        address(this),
                        block.timestamp
                    )
            {
                success = true;
            } catch {}
        }
        if (!success) {
            return;
        }

        _transfer(address(this), DEAD, amountSuckBurn);
        uint256 amountBackTokenTreasury = backToken.balanceOf(address(this)) -
            balanceBefore;
        backToken.transfer(treasuryWallet, amountBackTokenTreasury);

        emit SwapBack(amountSuckBurn, amountBackTokenTreasury, block.timestamp);
    }

    function doSwapBack() public onlyOwner {
        swapBack();
    }

    function takeFee(address sender, uint256 amount)
        internal
        returns (uint256)
    {
        uint256 feeAmount = (amount * totalFee) / feeDenominator;
        _transfer(sender, address(this), feeAmount);
        return amount - feeAmount;
    }

    function rescueToken(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(
            msg.sender,
            IERC20(tokenAddress).balanceOf(address(this))
        );
    }

    function clearStuckEthBalance() external onlyOwner {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(_msgSender()).call{value: amountETH}(
            new bytes(0)
        );
        require(success, "SUCKPEPE: ETH_TRANSFER_FAILED");
    }

    function clearStuckBalance() external onlyOwner {
        backToken.transfer(_msgSender(), backToken.balanceOf(address(this)));
    }

    function getCirculatingSupply() public view returns (uint256) {
        return totalSupply() - balanceOf(DEAD) - balanceOf(ZERO);
    }

    /*** ADMIN FUNCTIONS ***/
    function setSellFees(uint256 _treasuryFee, uint256 _burnFee)
        external
        onlyOwner
    {
        treasuryFee = _treasuryFee;
        burnFee = _burnFee;
        totalFee = _treasuryFee + _burnFee;
    }

    function setFeeReceivers(address _treasuryWallet) external onlyOwner {
        treasuryWallet = _treasuryWallet;
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setSwapBackSettings(bool _enabled) external onlyOwner {
        swapEnabled = _enabled;
    }

    function isPair(address account) public view returns (bool) {
        return _pairs.contains(account);
    }

    function addPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "SUCKPEPE: pair is the zero address");
        return _pairs.add(pair);
    }

    function delPair(address pair) public onlyOwner returns (bool) {
        require(pair != address(0), "SUCKPEPE: pair is the zero address");
        return _pairs.remove(pair);
    }

    function getMinterLength() public view returns (uint256) {
        return _pairs.length();
    }

    function getPair(uint256 index) public view returns (address) {
        require(index <= _pairs.length() - 1, "SUCKPEPE: index out of bounds");
        return _pairs.at(index);
    }

    receive() external payable {}
}

