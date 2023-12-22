// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";

contract TEST is  ERC20, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public maxSupply;
    uint256 public initSupply;


    mapping(address => bool) private isController;
    mapping(address => bool) private isExcludedFromFee;

    bool public tradingEnabled = false;

    uint256 public transferFeePercentage;
    address public feeDestination;

    constructor(uint256 _maxSupply, uint256 _initSupply)
        ERC20("TEST", "TESTING")
    {
        initSupply = _initSupply;
        maxSupply = _maxSupply;
        _mint(msg.sender, initSupply);
    }

    function mint(address to_, uint256 amount_)
        external
        onlyController
    {
        require(
            totalSupply().add(amount_) <= maxSupply,
            "Maximum supply reached"
        );
        _mint(to_, amount_);
    }

    function burn(address from_, uint256 amount_)
        external
        onlyController
    {
        _burn(from_, amount_);
    }

    event ControllerAdded(address newController);

    function addController(address toAdd_) external onlyOwner {
        isController[toAdd_] = true;
        emit ControllerAdded(toAdd_);
    }

    event ControllerRemoved(address controllerRemoved);

    function removeController(address toRemove_) external onlyOwner {
        isController[toRemove_] = false;
        emit ControllerRemoved(toRemove_);
    }

    modifier onlyController() {
        require(
            isController[_msgSender()],
            "Caller is not a controller"
        );
        _;
    }

    function enable_trading() public onlyOwner {
        tradingEnabled = true;
    }

    function setTransferFee(uint256 feePercentage) external onlyOwner {
        require(feePercentage <= 100, "Invalid fee percentage");
        transferFeePercentage = feePercentage;
    }

    function setFeeDestination(address destination) external onlyOwner {
        require(destination != address(0), "Invalid destination address");
        feeDestination = destination;
    }

    function excludeFromFee(address account) external onlyOwner {
        isExcludedFromFee[account] = true;
    }


    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(tradingEnabled, "Trading is currently disabled");

        uint256 transferFee = 0;
        if (!isExcludedFromFee[from] && !isExcludedFromFee[to]) {
            transferFee = amount.mul(transferFeePercentage).div(100);
            if (transferFee > 0) {
                super._transfer(from, feeDestination, transferFee);
            }
        }

        uint256 amountAfterFee = amount.sub(transferFee);
        super._transfer(from, to, amountAfterFee);
    }
}

