// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./ReentrancyGuardUpgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ISLNAProxy.sol";
import "./IVeToken2.sol";
import "./IVoter2.sol";
import "./IRouter.sol";
import "./ISolidlyFactory.sol";
import "./IPairFactory.sol";
import "./ICpSLNAConfigurator.sol";

contract CpSLNASolidStaker is ERC20Upgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Addresses used
    ISLNAProxy public proxy;
    IERC20Upgradeable public want;
    IERC20Upgradeable public native;
    IVeToken2 public ve;
    IVoter2 public solidVoter;
    IRouter public router;
    ICpSLNAConfigurator public configurator;

    uint256 public constant MAX = 10000; // 100%
    uint256 public constant MAX_RATE = 1e18;
    // Vote weight decays linearly over time. Lock time cannot be more than `MAX_LOCK` (4 years).
    uint256 public constant MAX_LOCK = 4 * 365 days;
    
    address public keeper;
    address public voter;
    address public polWallet;
    address public daoWallet;

    event CreateLock(address indexed user, uint256 amount, uint256 unlockTime);
    event Release(address indexed user, uint256 amount);
    event Deposit(uint256 amount);
    event NewManager(address _keeper, address _voter, address _polWallet, address _daoWallet);

    modifier onlyManager() {
        require(
            msg.sender == owner() || msg.sender == keeper,
            "CpSLNASolidStaker: MANAGER_ONLY"
        );
        _;
    }

    modifier onlyVoter() {
        require(msg.sender == voter, "CpSLNASolidStaker: VOTER_ONLY");
        _;
    }

    function init(
        string memory _name,
        string memory _symbol,
        address _proxy,
        address _keeper,
        address _voter,
        address _polWallet,
        address _daoWallet,
        address _configurator
    ) public initializer {
        __Ownable_init();
        __ERC20_init(_name, _symbol);
        proxy = ISLNAProxy(_proxy);
        want = IERC20Upgradeable(proxy.SLNA());
        ve = IVeToken2(proxy.ve());
        solidVoter = IVoter2(proxy.solidVoter());
        router = IRouter(proxy.router());
        configurator = ICpSLNAConfigurator(_configurator);
        native = IERC20Upgradeable(router.weth());

        keeper = _keeper;
        voter = _voter;
        polWallet = _polWallet;
        daoWallet = _daoWallet;
    }

    function depositAll() external {
        _deposit(want.balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) external {
        _deposit(_amount);
    }

    function depositVe(uint256 _tokenId) external nonReentrant whenNotPaused {
        require(!configurator.isPausedDepositVe(), "CpSLNASolidStaker: PAUSED");
        uint256 tokenId = proxy.mainTokenId();
        require(tokenId > 0, "CpSLNASolidStaker: NOT_ASSIGNED");
        uint256 currentPeg = getCurrentPeg();
        require(currentPeg >= configurator.maxPeg(), "CpSLNASolidStaker: NOT_MINT_WITH_UNDER_PEG");
        increaseUnlockTime();
        (uint256 _lockedAmount, ) = ve.locked(_tokenId);
        if (_lockedAmount > 0) {
            ve.transferFrom(msg.sender, address(proxy), _tokenId);
            proxy.merge(_tokenId);
            _mint(msg.sender, _lockedAmount);
            emit Deposit(_lockedAmount);
        }
    }

    function _deposit(uint256 _amount) internal nonReentrant whenNotPaused {
        require(!configurator.isPausedDeposit(), "CpSLNASolidStaker: PAUSED");
        uint256 tokenId = proxy.mainTokenId();
        require(tokenId > 0, "CpSLNASolidStaker: NOT_ASSIGNED");
        increaseUnlockTime();
        IRouter.Routes[] memory routes = new IRouter.Routes[](2);
        routes[0] = IRouter.Routes({
            from: address(want),
            to: address(native),
            stable: false
        });
        routes[1] = IRouter.Routes({
            from: address(native),
            to: address(this),
            stable: false
        });

        address pairAddress = ISolidlyFactory(solidVoter.factory()).getPair(address(native), address(this), false);
        require(pairAddress != address(0), "CpSLNASolidStaker: LP_INVALID");
        uint256 amountOut = router.getAmountsOut(_amount, routes)[routes.length];
        uint256 taxBuyingPercent = configurator.hasBuyingTax(address(this), pairAddress);
        amountOut = amountOut - amountOut * taxBuyingPercent / MAX;

        if (amountOut > _amount) {
            want.safeTransferFrom(msg.sender, address(this), _amount);
            IERC20Upgradeable(want).safeApprove(address(router), _amount);
            router.swapExactTokensForTokens(
                _amount,
                0,
                routes,
                msg.sender,
                block.timestamp
            );
            IERC20Upgradeable(want).safeApprove(address(router), 0);
        } else {
            uint256 _balanceBefore = balanceOfWant();
            want.safeTransferFrom(msg.sender, address(this), _amount);
            _amount = balanceOfWant() - _balanceBefore;

            if (_amount > 0) {
                _mint(msg.sender, _amount);
                uint256 balanceWant = balanceOfWant();
                want.safeTransfer(address(proxy), balanceWant);
                proxy.increaseAmount(balanceWant);
            }
        }

        emit Deposit(totalWant());
    }

    function increaseUnlockTime() public { 
        if (configurator.isAutoIncreaseLock()) {
            uint256 tokenId = proxy.mainTokenId();
            uint256 unlockTime = (block.timestamp + MAX_LOCK) / 1 weeks * 1 weeks;
            (, uint256 mainEndTime) = ve.locked(tokenId);
            if (unlockTime > mainEndTime) proxy.increaseUnlockTime();
        }
    }

    function totalWant() public view returns (uint256) {
        return balanceOfWant() + balanceOfWantInVeMain();
    }

    // Calculate how much 'want' is held by this contract
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function lockInfo()
        public
        view
        returns (
            uint256 endTime,
            uint256 secondsRemaining,
            bool shouldIncreaseLock
        )
    {
        uint256 tokenId = proxy.mainTokenId();
        (, endTime) = proxy.locked(tokenId);
        uint256 unlockTime = ((block.timestamp + MAX_LOCK) / 1 weeks) * 1 weeks;
        secondsRemaining = endTime > block.timestamp ? endTime - block.timestamp : 0;
        shouldIncreaseLock = configurator.isAutoIncreaseLock() && unlockTime > endTime;
    }

    function balanceOfWantInVeMain() public view returns (uint256 wants) {
        uint256 mainTokenId = proxy.mainTokenId();
        (wants, ) = proxy.locked(mainTokenId);
    }

    function circulatingSupply() public view returns (uint256) {
        uint256 excludedSupply = 0;
        address[] memory excluded = configurator.getExcluded();
        uint256 excludedLength = excluded.length;
        for (uint256 i = 0; i < excludedLength; i++) {
            excludedSupply = excludedSupply + balanceOf(excluded[i]);
        }

        return totalSupply() - excludedSupply;
    }

    // Reset current votes
    function resetVote() external onlyVoter {
        uint256 tokenId = proxy.mainTokenId();
        proxy.resetVote(tokenId);
    }

    function createMainLock(
        uint256 _amount,
        uint256 _lock_duration
    ) external onlyManager {
        require(_amount > 0, "CpSLNASolidStaker: ZERO_AMOUNT");
        want.safeTransferFrom(address(msg.sender), address(proxy), _amount);
        proxy.createMainLock(_amount, _lock_duration);
        _mint(msg.sender, _amount);

        emit CreateLock(msg.sender, _amount, _lock_duration);
    }

    // Release expired lock of a veToken owned by this address
    function release() external onlyManager {
        (uint endTime, , ) = lockInfo();
        require(endTime <= block.timestamp, "CpSLNASolidStaker: LOCKED");
        proxy.release();

        emit Release(msg.sender, balanceOfWant());
    }

    // Pause deposits
    function pause(bool _paused) external onlyManager {
        if (_paused) {
            _pause();
            proxy.pause();
        } else {
            _unpause();
            proxy.unpause();
        }
    }

    function setManager(
        address _keeper,
        address _voter,
        address _polWallet,
        address _daoWallet
    ) external onlyManager {
        keeper = _keeper;
        voter = _voter;
        polWallet = _polWallet;
        daoWallet = _daoWallet;
        emit NewManager(_keeper, _voter, _polWallet, _daoWallet);
    }

    function getCurrentPeg() public view returns (uint256) {
        ISolidlyFactory factory = ISolidlyFactory(solidVoter.factory());
        address pairAddress = factory.getPair(address(native), address(this), false);
        require(pairAddress != address(0), "CpSLNASolidStaker: LP_INVALID");
        IPairFactory pair = IPairFactory(pairAddress);
        address token0 = pair.token0();
        (uint256 _reserve0, uint256 _reserve1, ) = pair.getReserves();

        uint256 peg1 = 0;
        if (token0 == address(this)) {
            peg1 = _reserve1 * MAX_RATE / _reserve0;
        } else {
            peg1 = _reserve0 * MAX_RATE / _reserve1;
        }

        address pair2Address = factory.getPair(address(native), address(want), false);
        IPairFactory pair2 = IPairFactory(pair2Address);
        (_reserve0, _reserve1, ) = pair2.getReserves();
        token0 = pair2.token0();
        if (token0 == address(native)) {
            return peg1 * _reserve1 / _reserve0;
        } else {
            return peg1 * _reserve0 / _reserve1;
        }
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        require(polWallet != address(0),"require to set polWallet address");
        address sender = _msgSender();
        uint256 taxAmount = _chargeTaxTransfer(sender, to, amount);
        _transfer(sender, to, amount - taxAmount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        require(polWallet != address(0),"require to set polWallet address");
        
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);

        uint256 taxAmount = _chargeTaxTransfer(from, to, amount);
        _transfer(from, to, amount - taxAmount);
        return true;
    }

    function _chargeTaxTransfer(address from, address to, uint256 amount) internal returns (uint256) {
        uint256 taxSellingPercent = configurator.hasSellingTax(from, to);
        uint256 taxBuyingPercent = configurator.hasBuyingTax(from, to);
        uint256 taxPercent = taxSellingPercent > taxBuyingPercent ? taxSellingPercent: taxBuyingPercent;
		if(taxPercent > 0) {
            uint256 taxAmount = amount * taxPercent / MAX;
            uint256 amountToDead = taxAmount / 2;
            _transfer(from, configurator.deadWallet(), amountToDead);
            _transfer(from, polWallet, taxAmount - amountToDead);
            return taxAmount;
		}

        return 0;
    }

    function setSolidVoter(address _solidVoter) external onlyManager {
        proxy.setSolidVoter(_solidVoter);
        solidVoter = IVoter2(_solidVoter);
    }

    function setVeDist(address _veDist) external onlyManager {
        proxy.setVeDist(_veDist);
    }
}
