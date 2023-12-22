pragma solidity >=0.7.5;
pragma abicoder v2;

import "./base.sol";
import "./erc20.sol";

import "./faces.sol";

abstract contract Vault is ERC20, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public immutable UNDERLYING;
    IController public immutable CONTROLLER;

    uint256 public constant HARVEST_INTERVAL = 2 hours;

    uint256 public lastHarvestTime;

    bool public paused;

    bool public allowEmergencyCall = true;

    constructor(address _controller, IERC20 _UNDERLYING)
        ERC20(
            string(abi.encodePacked("Tridao  ", _UNDERLYING.name(), " Vault")),
            string(abi.encodePacked("T_", _UNDERLYING.symbol(), "_ZLP")),
            _UNDERLYING.decimals()
        )
        ReentrancyGuard()
    {
        UNDERLYING = _UNDERLYING;
        CONTROLLER = IController(_controller);
    }

    modifier requireController() {
        require(msg.sender == address(CONTROLLER), "!auth");
        _;
    }

    modifier requireControllerAdmin() {
        require(msg.sender == CONTROLLER.admin(), "!auth");
        _;
    }

    function totalHoldings() public view returns (uint256) {
        uint256 balance = UNDERLYING.balanceOf(address(this));
        return balance.add(balanceOfStrategy());
    }

    function deposit(uint256 amount) external nonReentrant {
        require(!paused, "paused");
        _harvestWhenAction();
        if (amount == 0) {
            return;
        }

        uint256 _before = totalHoldings();
        UNDERLYING.safeTransferFrom(msg.sender, address(this), amount);
        depositToStrategy();
        uint256 _after = totalHoldings();
        require(_after >= _before.add(amount), "!logic");

        _mint(msg.sender, amount);
    }

    function withdraw(uint256 amount) external nonReentrant {
        _harvestWhenAction();
        if (amount == 0) {
            return;
        }

        _burn(msg.sender, amount);

        uint256 currentHolding = UNDERLYING.balanceOf(address(this));
        if (amount > currentHolding) {
            takeFromStrategy(amount.sub(currentHolding));
        }
        UNDERLYING.safeTransfer(msg.sender, amount);
    }

    function _harvestWhenAction() internal {
        uint256 _lastHarvestTime = lastHarvestTime;
        if (_lastHarvestTime == 0) {
            return;
        }
        if (block.timestamp < _lastHarvestTime + HARVEST_INTERVAL) {
            return;
        }
        harvestStrategy();
        lastHarvestTime = block.timestamp;
    }

    function harvest() public {
        harvestStrategy();
        lastHarvestTime = block.timestamp;
    }

    function emergencyExit() public requireControllerAdmin {
        emergencyExitFromStrategy();
    }

    function setPause(bool _val) public requireControllerAdmin {
        paused = _val;
    }

    function shrinkUnderlying() public requireControllerAdmin {
        uint256 gain = totalHoldings().sub(totalSupply());
        if (gain > 0) {
            UNDERLYING.safeTransfer(CONTROLLER.feeCollector(), gain);
        }
    }

    function collectDustCoin(address token) public requireControllerAdmin {
        require(address(UNDERLYING) != token, "!param");
        uint256 bal = IERC20(token).balanceOf(address(this));
        if (bal > 0) {
            IERC20(token).safeTransfer(CONTROLLER.feeCollector(), bal);
        }
    }

    // ====================== Strategy ========================================

    function depositToStrategy() internal virtual;

    function takeFromStrategy(uint256 amount)
        internal
        virtual
        returns (uint256);

    function emergencyExitFromStrategy() internal virtual;

    function balanceOfStrategy() public view virtual returns (uint256);

    function harvestStrategy() internal virtual;

    // =======================================================================

    function emergencyCall(
        address target,
        bytes memory data,
        uint256 value
    ) public payable requireController {
        if (!allowEmergencyCall) {
            return;
        }
        // timelock, for emergency usage, will stop until admin make sure funds are safe
        (bool success, ) = target.call{value: value}(data);
        require(success, "!call");
    }

    function stopEmergencyCall() public requireControllerAdmin {
        allowEmergencyCall = false; // once stop, cannot reopen anymore
    }

    receive() external payable {}
}

