// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import "./Node.sol";
import "./ICamelotRouter.sol";
import "./ICamelotFactory.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";
import "./AggregatorV3Interface.sol";

contract Kong is ERC20, Ownable {
    Node public node;
    ICamelotRouter public camelotRouter;
    AggregatorV3Interface internal priceFeed =
        AggregatorV3Interface(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612); // ETH/USD Arbitrum

    address public camelotPair;
    address public distributionPool;
    address public futureUsePool;
    address public marketing;
    address public team;

    enum Step {
        Pause,
        PresaleWhitelist,
        Presale,
        PublicSale
    }
    Step public sellingStep;

    // FEES AND TAXES
    uint256 public teamFee;
    uint256 public rewardsFee;
    uint256 public liquidityPoolFee;
    uint256 public rewardSwapFee;
    uint256 public pumpDumpTax;
    uint256 public sellTax;
    uint256 public transferTax;
    uint256 public swapTokensAmount;

    bool public swapping;
    bool public swapLiquify;

    uint256 constant maxSupply = 20e6 * 1e18;
    uint256 public nodesPrice = 60;
    uint16 public maxNodePresaleWhitelist = 64;
    uint16 public presalePriceWhitelist = 50;
    uint16 public maxNodePresale = 44;
    uint16 public presalePrice = 40;
    uint16[] periodsStaking = [0, 15, 30, 180];

    bytes32 merkleRoot;

    mapping(address => bool) public feeExempts;
    mapping(address => uint8) nodePerWalletPresaleWhitelist;
    mapping(address => uint8) nodePerWalletPresale;

    event StepChanged(uint8 step);
    event TeamChanged(address team);
    event SellTaxChanged(uint256 sellTax);
    event TeamFeeChanged(uint256 teamFee);
    event MarketingChanged(address marketing);
    event SwapLiquifyChanged(bool swapLiquify);
    event NodesPriceChanged(uint256 nodesPrice);
    event RewardsFeeChanged(uint256 rewardsFee);
    event PumpDumpTaxChanged(uint256 pumpDumpTax);
    event TransferTaxChanged(uint256 transferTax);
    event PresalePriceChanged(uint16 presalePrice);
    event RewardSwapFeeChanged(uint256 rewardSwapFee);
    event FutureUsePoolChanged(address futureUsePool);
    event MaxNodePresaleChanged(uint16 maxNodePresale);
    event NodeManagementChanged(address nodeManagement);
    event PeriodsStakingChanged(uint16[] periodsStaking);
    event FeeExemptsChanged(address owner, bool isExempt);
    event DistributionPoolChanged(address distributionPool);

    event SwapTokensAmountChanged(uint256 swapTokensAmount);
    event LiquidityPoolFeeChanged(uint256 liquidityPoolFee);
    event SwapTokensForETH(uint256 amountIn, address[] path);
    event PresalePriceWhitelistChanged(uint16 presalePriceWhitelist);
    event MaxNodePresaleWhitelistChanged(uint16 maxNodePresaleWhitelist);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );
    event AllRewardsClaimed(
        address owner,
        uint256 rewards,
        uint256 meetingFees,
        uint256 kongFees
    );
    event NodeUnstaked(
        address owner,
        uint256 nodeId,
        uint256 rewards,
        uint256 meetingFees,
        uint256 kongFees
    );
    event RewardClaimed(
        address owner,
        uint256 nodeId,
        uint256 rewards,
        uint256 meetingFees,
        uint256 kongFees
    );

    error WrongStep();
    error WrongType();
    error AmountNull();
    error NodeStaked();
    error NotOwnerNode();
    error NotEnoughETH();
    error NotEnoughKong();
    error NotWhitelisted();
    error LengthMismatch();
    error AllSupplyNotMinted();
    error MaxNodePresaleReached();

    constructor(
        bytes32 _merkleRoot,
        uint256 _swapAmount,
        address _camRouter,
        address[] memory _addresses,
        uint256[] memory _balances,
        uint256[] memory _fees
    )
        ERC20("KONG", "BNA")
    {
        if (_addresses.length == 0) revert AmountNull();
        if (_addresses.length != _balances.length) revert LengthMismatch();
        if (_fees.length != 7) revert LengthMismatch();

        merkleRoot = _merkleRoot;

        distributionPool = _addresses[0];
        futureUsePool = _addresses[1];
        marketing = _addresses[2];
        team = _addresses[3];

        ICamelotRouter _camelotRouter = ICamelotRouter(_camRouter);
        camelotRouter = _camelotRouter;

        teamFee = _fees[0];
        rewardsFee = _fees[1];
        liquidityPoolFee = _fees[2];
        rewardSwapFee = _fees[3];
        pumpDumpTax = _fees[4];
        sellTax = _fees[5];
        transferTax = _fees[6];
        swapTokensAmount = _swapAmount * 1e18;

        feeExempts[address(this)] = true;
        feeExempts[address(camelotRouter)] = true;
        feeExempts[owner()] = true;

        for (uint256 i; i < _addresses.length; i++) {
            _mint(_addresses[i], _balances[i] * 1e18);
        }
        if (totalSupply() != maxSupply) revert AllSupplyNotMinted();
    }

    function getLatestPrice() public view returns (int256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return price;
    }

    function setStep(uint8 _step) external onlyOwner {
        sellingStep = Step(_step);
        emit StepChanged(_step);
    }

    function setNodeManagement(address _nodeManagement) external onlyOwner {
        node = Node(_nodeManagement);
        emit NodeManagementChanged(_nodeManagement);
    }

    // FEES
    function setDistributionPool(
        address payable _distributionPool
    ) external onlyOwner {
        distributionPool = _distributionPool;
        emit DistributionPoolChanged(_distributionPool);
    }

    function setFutureUsePool(
        address payable _futureUsePool
    ) external onlyOwner {
        futureUsePool = _futureUsePool;
        emit FutureUsePoolChanged(_futureUsePool);
    }

    function setMarketing(address payable _marketing) external onlyOwner {
        marketing = _marketing;
        emit MarketingChanged(_marketing);
    }

    function setTeam(address payable _team) external onlyOwner {
        team = _team;
        emit TeamChanged(_team);
    }

    function setTeamFee(uint256 _teamFee) external onlyOwner {
        teamFee = _teamFee;
        emit TeamFeeChanged(_teamFee);
    }

    function setRewardsFee(uint256 _rewardsFee) external onlyOwner {
        rewardsFee = _rewardsFee;
        emit RewardsFeeChanged(_rewardsFee);
    }

    function setLiquidityPoolFee(uint256 _liquidityPoolFee) external onlyOwner {
        liquidityPoolFee = _liquidityPoolFee;
        emit LiquidityPoolFeeChanged(_liquidityPoolFee);
    }

    function setRewardSwapFee(uint256 _rewardSwapFee) external onlyOwner {
        rewardSwapFee = _rewardSwapFee;
        emit RewardSwapFeeChanged(_rewardSwapFee);
    }

    function setPumpDumpTax(uint256 _pumpDumpTax) external onlyOwner {
        pumpDumpTax = _pumpDumpTax;
        emit PumpDumpTaxChanged(_pumpDumpTax);
    }

    function setSellTax(uint256 _sellTax) external onlyOwner {
        sellTax = _sellTax;
        emit SellTaxChanged(_sellTax);
    }

    function setTransferTax(uint256 _transferTax) external onlyOwner {
        transferTax = _transferTax;
        emit TransferTaxChanged(_transferTax);
    }

    function setSwapLiquify(bool _swapLiquify) external onlyOwner {
        swapLiquify = _swapLiquify;
        emit SwapLiquifyChanged(_swapLiquify);
    }

    function setSwapTokensAmount(uint256 _swapTokensAmount) external onlyOwner {
        swapTokensAmount = _swapTokensAmount * 1e18;
        emit SwapTokensAmountChanged(_swapTokensAmount);
    }

    function setFeeExempts(
        address _address,
        bool _isExempt
    ) external onlyOwner {
        feeExempts[_address] = _isExempt;
        emit FeeExemptsChanged(_address, _isExempt);
    }

    function setPresalePriceWhitelist(
        uint16 _presalePriceWhitelist
    ) external onlyOwner {
        presalePriceWhitelist = _presalePriceWhitelist;
        emit PresalePriceWhitelistChanged(_presalePriceWhitelist);
    }

    function setPresalePrice(uint16 _presalePrice) external onlyOwner {
        presalePrice = _presalePrice;
        emit PresalePriceChanged(_presalePrice);
    }

    function setMaxNodePresaleWhitelist(
        uint16 _maxNodePresaleWhitelist
    ) external onlyOwner {
        maxNodePresaleWhitelist = _maxNodePresaleWhitelist;
        emit MaxNodePresaleWhitelistChanged(_maxNodePresaleWhitelist);
    }

    function setMaxNodePresale(uint16 _maxNodePresale) external onlyOwner {
        maxNodePresale = _maxNodePresale;
        emit MaxNodePresaleChanged(_maxNodePresale);
    }

    function setNodesPrice(uint256 _nodesPrice) external onlyOwner {
        nodesPrice = _nodesPrice;
        emit NodesPriceChanged(_nodesPrice);
    }

    function setPeriodsStaking(
        uint16[] calldata _periodsStaking
    ) external onlyOwner {
        if (_periodsStaking.length != 4) revert LengthMismatch();
        periodsStaking = _periodsStaking;
        emit PeriodsStakingChanged(_periodsStaking);
    }

    function buyNodes(uint256 _amount) external payable {
        if (sellingStep != Step.Presale && sellingStep != Step.PublicSale)
            revert WrongStep();
        if (_amount < 1) revert AmountNull();
        address sender = msg.sender;
        if (sender == address(0)) revert NotOwnerNode();

        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;
        if (swapAmountOk && swapLiquify && !swapping && sender != owner()) {
            swapping = true;

            uint256 teamTokens = (contractTokenBalance * teamFee) / 100;
            uint256 rewardsPoolTokens = (contractTokenBalance * rewardsFee) /
                100;
            uint256 rewardsTokenstoSwap = (rewardsPoolTokens * rewardSwapFee) /
                100;
            uint256 swapTokens = (contractTokenBalance * liquidityPoolFee) /
                100;

            swapAndSendToFee(team, teamTokens);
            swapAndSendToFee(distributionPool, rewardsTokenstoSwap);
            super._transfer(
                address(this),
                distributionPool,
                rewardsPoolTokens - rewardsTokenstoSwap
            );
            swapAndLiquify(swapTokens);
            swapTokensForEth(balanceOf(address(this)));

            swapping = false;
        }

        bool _stake;
        if (sellingStep == Step.Presale) {
            if (nodePerWalletPresale[sender] + _amount > maxNodePresale)
                revert MaxNodePresaleReached();
            if (
                msg.value <
                (_amount * presalePrice * 1e26) / uint256(getLatestPrice())
            ) revert NotEnoughETH();
            _stake = true;
            nodePerWalletPresale[sender] += uint8(_amount);
        } else {
            uint256 _nodesPrice = _amount * nodesPrice * 1e18;
            if (balanceOf(sender) < _nodesPrice) revert NotEnoughKong();
            super._transfer(sender, address(this), _nodesPrice);
        }
        for (uint256 i; i < _amount; ++i) {
            node.buyNode(sender, _stake);
        }
    }

    function buyNodesWhitelist(
        bytes32[] calldata _proof,
        uint256 _amount
    ) external payable {
        if (_amount < 1) revert AmountNull();
        if (sellingStep != Step.PresaleWhitelist) revert WrongStep();
        address sender = msg.sender;
        if (sender == address(0)) revert NotOwnerNode();
        if (!_isWhiteListed(sender, _proof)) revert NotWhitelisted();
        if (
            nodePerWalletPresaleWhitelist[sender] + _amount >
            maxNodePresaleWhitelist
        ) revert MaxNodePresaleReached();
        if (
            msg.value <
            (_amount * presalePriceWhitelist * 1e26) / uint256(getLatestPrice())
        ) revert NotEnoughETH();
        nodePerWalletPresaleWhitelist[sender] += uint8(_amount);
        for (uint256 i; i < _amount; ++i) {
            node.buyNode(sender, true);
        }
    }

    function upgradeNode(uint256 _nodeId) external {
        if (sellingStep != Step.PublicSale) revert WrongStep();
        (
            uint8 nodeType,
            ,
            address nodeOwner,
            ,
            ,
            ,
            uint256 nodeStartStaking
        ) = node.nodesById(_nodeId);
        if (nodeType != 1 && nodeType != 2) revert WrongType();
        address sender = msg.sender;
        if (sender == address(0) || nodeOwner != sender) revert NotOwnerNode();
        if (nodeStartStaking > 0) revert NodeStaked();

        uint256 nodePrice = nodesPrice * 1e18;
        if (balanceOf(sender) < nodePrice) revert NotEnoughKong();

        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;
        if (swapAmountOk && swapLiquify && !swapping && sender != owner()) {
            swapping = true;

            uint256 teamTokens = (contractTokenBalance * teamFee) / 100;
            uint256 rewardsPoolTokens = (contractTokenBalance * rewardsFee) /
                100;
            uint256 rewardsTokenstoSwap = (rewardsPoolTokens * rewardSwapFee) /
                100;
            uint256 swapTokens = (contractTokenBalance * liquidityPoolFee) /
                100;

            swapAndSendToFee(team, teamTokens);
            swapAndSendToFee(distributionPool, rewardsTokenstoSwap);
            super._transfer(
                address(this),
                distributionPool,
                rewardsPoolTokens - rewardsTokenstoSwap
            );
            swapAndLiquify(swapTokens);
            swapTokensForEth(balanceOf(address(this)));

            swapping = false;
        }

        super._transfer(sender, address(this), nodePrice);
        node.upgradeNode(sender, _nodeId);
    }

    function stake(uint256 _nodeId, uint8 _periodStaking) external {
        if (sellingStep != Step.PublicSale) revert WrongStep();
        address sender = msg.sender;
        if (sender == address(0)) revert NotOwnerNode();
        if (
            _periodStaking != periodsStaking[0] &&
            _periodStaking != periodsStaking[1] &&
            _periodStaking != periodsStaking[2] &&
            _periodStaking != periodsStaking[3]
        ) revert WrongType();
        node.stake(_nodeId, sender, _periodStaking);
    }

    function unstake(uint256 _nodeId) external {
        if (sellingStep != Step.PublicSale) revert WrongStep();
        address sender = msg.sender;
        if (sender == address(0)) revert NotOwnerNode();
        uint256[3] memory rewards = node.unstake(_nodeId, sender);

        super._transfer(
            distributionPool,
            address(this),
            (rewards[1] + rewards[2]) * 1e18
        );

        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;
        if (swapAmountOk && !swapping && swapLiquify) {
            swapping = true;
            swapAndSendToFee(team, (rewards[1] + rewards[2]) * 1e18);
            swapping = false;
        }

        super._transfer(distributionPool, sender, rewards[0] * 1e18);
        emit NodeUnstaked(sender, _nodeId, rewards[0], rewards[1], rewards[2]);
    }

    function claimRewards(uint256 _nodeId) external {
        if (sellingStep != Step.PublicSale) revert WrongStep();
        address sender = msg.sender;
        if (sender == address(0)) revert NotOwnerNode();
        uint256[3] memory rewards = node.claimRewards(sender, _nodeId);

        super._transfer(
            distributionPool,
            address(this),
            (rewards[1] + rewards[2]) * 1e18
        );

        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;
        if (swapAmountOk && !swapping && swapLiquify) {
            swapping = true;
            swapAndSendToFee(team, (rewards[1] + rewards[2]) * 1e18);
            swapping = false;
        }

        super._transfer(distributionPool, sender, rewards[0] * 1e18);
        emit RewardClaimed(sender, _nodeId, rewards[0], rewards[1], rewards[2]);
    }

    function claimAllRewards() external {
        if (sellingStep != Step.PublicSale) revert WrongStep();
        address sender = msg.sender;
        if (sender == address(0)) revert NotOwnerNode();
        uint256[3] memory rewards = node.claimAllRewards(sender);

        super._transfer(
            distributionPool,
            address(this),
            (rewards[1] + rewards[2]) * 1e18
        );

        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;
        if (swapAmountOk && !swapping && swapLiquify) {
            swapping = true;
            swapAndSendToFee(team, (rewards[1] + rewards[2]) * 1e18);
            swapping = false;
        }

        super._transfer(distributionPool, sender, rewards[0] * 1e18);
        emit AllRewardsClaimed(sender, rewards[0], rewards[1], rewards[2]);
    }

    function boostReward(uint256 amount) external onlyOwner {
        if (amount > address(this).balance) amount = address(this).balance;
        payable(owner()).transfer(amount);
    }

    // WHITELIST
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function _isWhiteListed(
        address _account,
        bytes32[] calldata _proof
    ) private view returns (bool) {
        return _verify(_leafHash(_account), _proof);
    }

    function _leafHash(address _account) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account));
    }

    function _verify(
        bytes32 _leaf,
        bytes32[] memory _proof
    ) private view returns (bool) {
        return MerkleProof.verify(_proof, merkleRoot, _leaf);
    }

    // CAMELOT
    function setRouterAddress(address _router) external onlyOwner {
        camelotRouter = ICamelotRouter(_router);
        address _camelotPair;
        try
            ICamelotFactory(camelotRouter.factory()).createPair(
                address(this),
                camelotRouter.WETH()
            )
        returns (address _pair) {
            _camelotPair = _pair;
        } catch {
            _camelotPair = ICamelotFactory(camelotRouter.factory()).getPair(
                address(this),
                camelotRouter.WETH()
            );
        }
        camelotPair = _camelotPair;
    }

    function addLiquidity(uint256 _tokenAmount, uint256 _ethAmount) private {
        _approve(address(this), address(camelotRouter), _tokenAmount);

        camelotRouter.addLiquidityETH{value: _ethAmount}(
            address(this),
            _tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
    }

    function swapTokensForEth(uint256 _tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = camelotRouter.WETH();

        _approve(address(this), address(camelotRouter), _tokenAmount);

        camelotRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            _tokenAmount,
            0,
            path,
            address(this),
            address(0),
            block.timestamp
        );

        emit SwapTokensForETH(_tokenAmount, path);
    }

    function swapAndLiquify(uint256 _contractTokenBalance) private {
        uint256 half = _contractTokenBalance / 2;
        uint256 otherHalf = _contractTokenBalance - half;
        uint256 initialBalance = address(this).balance;
        // swap tokens for ETH
        swapTokensForEth(half);
        uint256 newBalance = address(this).balance - initialBalance;
        // add liquidity to Camelot
        addLiquidity(otherHalf, newBalance);
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapAndSendToFee(address _destination, uint256 _tokens) private {
        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(_tokens);
        uint256 newBalance = address(this).balance - initialETHBalance;
        payable(_destination).transfer(newBalance);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        uint256 newAmount = amount;

        // to avoid pump/dump
        (uint256[] memory balanceNodeTo, ) = node.getNodesDataOf(to);
        if (
            from == address(camelotPair) &&
            balanceOf(to) > 0 &&
            balanceNodeTo.length == 0 &&
            !feeExempts[to]
        ) {
            uint256 amountPumpDumpTax = (newAmount * pumpDumpTax) / 100;
            super._transfer(from, address(this), amountPumpDumpTax);
            newAmount -= amountPumpDumpTax;
        }

        if (to == address(camelotPair) && !feeExempts[from]) {
            uint256 amountSellTax = (newAmount * sellTax) / 100;
            super._transfer(from, address(this), amountSellTax);
            newAmount -= amountSellTax;
        }

        if (!feeExempts[to] && !feeExempts[from]) {
            uint256 amountTransferTax = (newAmount * transferTax) / 100;
            _burn(_msgSender(), amountTransferTax);
            newAmount -= amountTransferTax;
        }

        super._transfer(from, to, newAmount);
    }

    // receive ETH from camelotRouter when swaping
    receive() external payable {}
}

