/**
 *  SPDX-License-Identifier: MIT
 *  Tokenomics:
 * - 每笔交易的总税额为 10%。
 * - 4% 的税款按比例分配给所有持有人。
 * - 2% 的营销、竞赛和庆祝分发活动税。
 * 对投资者完全透明地使用。
 * - 4% 的开发和团队费用。 没有人应该免费工作。
 * - 从一个钱包到另一个钱包的正常转账是 100% 免税的。
 * - 我们 DAPP 收入的 50% 将按比例分配
 * MCoin 的所有持有者。
 * - Burn 和 CEX 钱包不包括在税收/收入分配中。
 * - 0 个初始开发或团队钱包。
 *
 *  We are here to disrupt. We are here for MSHK.
 *
 *  Website -------- mshk.top
 */

pragma solidity ^0.8.18;

import "./ContextUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./SafeMath.sol";

import "./console.sol";

/**
 * @title R3Token token contract.
 * @author The R3Token team.
 */
contract R3Token is
    ContextUpgradeable,
    IERC20Upgradeable,
    IERC20MetadataUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => uint256) private _supplyOwned;

    /**
     * 排除掉的手续费列表
     * */
    mapping(address => bool) private _excludedFromTaxes;

    /**
     * 保存流动池合约的地址
     */
    mapping(address => bool) private _pair;

    // https://arbiscan.io/
    address private constant _factoryAddress =
        0x6554AD1Afaa3f4ce16dc31030403590F467417A6;
    address private constant _routerAddress =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    /**
     * UniswapV2Factory 部署在0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f以太坊主网上，以及Ropsten、Rinkeby、Görli和Kovan测试网。
     * */
    // address private constant _factoryAddress =
    //     0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    /**
     * UniswapV2Router02 部署在0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D以太坊主网上，以及Ropsten、Rinkeby、Görli和Kovan测试网。
     * */
    // address private constant _routerAddress =
    //     0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * 流动性钱包地址
     */
    address private _mobilityAddress;

    /**
     * 早期投资人钱包地址
     */
    address private _earlyInvestorsAddress;

    /**
     * 战略储备钱包地址
     */
    address private _strategicReserveAddress;

    /**
     * 捐赠钱包地址
     */
    address private _donateAddress;

    /**
     * 空投钱包地址
     */
    address private _airdropAddress;

    /**
     * 质押钱包地址
     */
    address private _pledgeAddress;

    /**
     * 资管团队奖励比例和地址
     */
    uint256 private _assetManagementTax;
    address private _assetManagementTaxAddress;

    /**
     * 营销团队奖励比例和地址
     */
    uint256 private _marketingTax;
    address private _marketingTaxAddress;

    /**
     * 质押池奖励比例和地址
     */
    uint256 private _pledgePoolTax;
    address private _pledgePoolTaxAddress;

    /**
     * 当要兑换ETH时的 最低点位要求
     */
    uint256 private _taxSwapThreshold;

    /**
     * unint256 最大单位
     */
    uint256 private constant _MAX_UINT = type(uint256).max;

    /**
     * 最大转帐限制
     */
    uint256 private _maxTransferLimit;

    IUniswapV2Factory private _factory;
    IUniswapV2Router02 private _router;

    /**
     * 是否在兑换中的标记
     */
    bool private _inSwap;

    /**
     * 更改资管团队税收地址的事件
     */
    event AssetManagementTaxAddressChange(
        address indexed from,
        address indexed to
    );
    /**
     * 更改营销团队税收地址的事件
     */
    event MarketingTaxAddressChange(address indexed from, address indexed to);
    /**
     * 更改质押池税收地址的事件
     */
    event PledgePoolTaxTaxAddressChange(
        address indexed from,
        address indexed to
    );
    /**
     * 取消到排除税收事件列表事件
     */
    event IncludeInTaxes(address indexed account);
    /**
     * 添加到排除税收事件列表事件
     */
    event ExcludeFromTaxes(address indexed account);
    /**
     * 添加Swap事件
     */
    event AddPair(address indexed pairAddress);
    /**
     * 启用最大金额限制事件
     */
    event EnableTransferLimit(uint256 limit);
    /**
     * 禁用最大金额限制事件
     */
    event DisableTransferLimit(uint256 limit);
    /**
     * 调整转换ETH最低点位要求事件
     */
    event TaxSwapThresholdChange(uint256 threshold);

    /**
     * 更改税收事件
     */
    event TaxesChange(
        uint256 rewardsTax,
        uint256 marketingTax,
        uint256 pledgePoolTax
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    // 需要此方法来防止未经授权的升级，因为在 UUPS 模式中，升级是从实现合约完成的，而在透明代理模式中，升级是通过代理合约完成的
    function _authorizeUpgrade(address) internal override onlyOwner {}

    // 可升级的合约应该有一个initialize方法来代替构造函数，并且initializer关键字确保合约只被初始化一次
    function initialize(string memory name_, string memory symbol_)
        public
        initializer
    {
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();

        __UUPSUpgradeable_init();

        _name = name_;
        _symbol = symbol_;

        // 发行指定数量货币
        _mint(_msgSender(), 10000000000 * 10**decimals());

        // 初始化最大转帐限制
        _maxTransferLimit = _totalSupply;

        // 初始化 swap 时的点位要求 总量 100 亿，小于100万时不能兑换
        _taxSwapThreshold = 1000000 * 10**decimals();

        // 初始化 Uniswap
        _router = IUniswapV2Router02(_routerAddress);
        _factory = IUniswapV2Factory(_factoryAddress);

        // addPair(_factory.createPair(address(this), '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2')); // https://etherscan.io/ - WETH
        // addPair(_factory.createPair(address(this), '0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6')); // https://goerli.etherscan.io/ - WETH
        addPair(
            _factory.createPair(
                address(this),
                0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
            )
        ); // https://arbiscan.io/ - WETH
        // addPair(
        //     _factory.createPair(
        //         address(this),
        //         "0xe39Ab88f8A4777030A534146A9Ca3B52bd5D43A3"
        //     )
        // ); // https://goerli.arbiscan.io/ - WETH

        // 在税收中排除掉合约和创建者
        excludeFromTaxes(address(this));
        excludeFromTaxes(_msgSender());

        // 流动性钱包地址
        // _mobilityAddress = 0xc95Bb33FF616dD75a5Aea55dA858167caa6FdF04;
        // _mobilityAddress = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // addr1
        _mobilityAddress = 0x744559f81df636b7A118Fa2AfF3b2852d368129f; // eth 新钱包地址，测试用
        excludeFromTaxes(_mobilityAddress);

        // 早期投资人钱包地址
        // _earlyInvestorsAddress = 0x68B000E3FF9b7d1Ea7EB8e2622d1a57a58ed992e;
        _earlyInvestorsAddress = 0x0BFd206c851729590DDAdfCa9439b30aD2AAbf9F;
        excludeFromTaxes(_earlyInvestorsAddress);

        // 战略储备钱包地址
        _strategicReserveAddress = 0xC3FaC739D6C39f7cfd7ace84EC1e428b0B49BaA6;
        excludeFromTaxes(_strategicReserveAddress);

        // 捐赠钱包地址
        _donateAddress = 0xA9A9b1e7A0807378d8696777c4b2183483575D79;
        excludeFromTaxes(_donateAddress);

        // 空投钱包
        _airdropAddress = 0x16B638B831Fe9974eF4b9c23bB93D2D6F74aa211;
        excludeFromTaxes(_airdropAddress);

        // 质押钱包
        _pledgeAddress = 0x1D347f4faF6d4bc992EE84146dE861D879A9bD52;
        excludeFromTaxes(_pledgeAddress);

        // 资管交易税地址
        _assetManagementTax = 5;
        _assetManagementTaxAddress = 0x6f7D6aC77a57AbC700a06c9Bf677585aa57270c4;
        excludeFromTaxes(_pledgePoolTaxAddress);

        // 营销交易税地址
        _marketingTax = 2;
        _marketingTaxAddress = 0xDB9fFa1673Ea43A471524c6891470Fb339549670;
        excludeFromTaxes(_marketingTaxAddress);

        // 质押池交易税地址
        _pledgePoolTax = 3;
        _pledgePoolTaxAddress = 0x5db34744660Cc33bDF89AF703b1137a73b168B1C;
        excludeFromTaxes(_pledgePoolTaxAddress);

        // 15%（流动性钱包，数量15 0000 0000）
        transfer(
            _mobilityAddress,
            SafeMath.div(SafeMath.mul(_totalSupply, 15), 100)
        );

        // 30%（早期投资人钱包，数量30 0000 0000）
        transfer(
            _earlyInvestorsAddress,
            SafeMath.div(SafeMath.mul(_totalSupply, 30), 100)
        );

        // 10%（战略储备钱包，数量10 0000 0000）
        transfer(
            _strategicReserveAddress,
            SafeMath.div(SafeMath.mul(_totalSupply, 10), 100)
        );

        // 2%（捐赠钱包，数量2 0000 0000）
        transfer(
            _donateAddress,
            SafeMath.div(SafeMath.mul(_totalSupply, 2), 100)
        );

        // 8%（空投余额钱包，数量8 0000 0000；每次空投转出至：0xcE199E5A7f8832D77DE0730C3E1d111Bca61EBc8)
        transfer(
            _airdropAddress,
            SafeMath.div(SafeMath.mul(_totalSupply, 8), 100)
        );

        // 35%（质押钱包，数量35 0000 0000）
        transfer(
            _pledgeAddress,
            SafeMath.div(SafeMath.mul(_totalSupply, 35), 100)
        );

        // 每次转帐金额最大限制
        enableTransferLimit();
    }

    //
    modifier swapLock() {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = SafeMath.add(_totalSupply, amount);
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _supplyOwned[account] = SafeMath.add(_supplyOwned[account], amount);
        }
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    // function burnFrom(address account, uint256 amount) public virtual {
    //     _spendAllowance(account, _msgSender(), amount);
    //     _burn(account, amount);
    // }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _supplyOwned[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _supplyOwned[account] = SafeMath.sub(accountBalance, amount);
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply = SafeMath.sub(_totalSupply, amount);
        }

        emit Transfer(account, address(0), amount);
    }

    /**
     * Returns the current assetManagement tax.
     */
    function assetManagementTax() public view returns (uint256) {
        return _assetManagementTax;
    }

    /**
     * Returns the current marketing tax.
     */
    function marketingTax() public view returns (uint256) {
        return _marketingTax;
    }

    /**
     * Returns the current pledgePool tax.
     */
    function pledgePoolTax() public view returns (uint256) {
        return _pledgePoolTax;
    }

    /**
     * 返回最大奖励比例.
     */
    function totalTaxes() public view returns (uint256) {
        return
            SafeMath.add(
                SafeMath.add(_assetManagementTax, _marketingTax),
                _pledgePoolTax
            );
    }

    /**
     * 返回交换ETH时的点位.
     */
    function taxSwapThreshold() public view returns (uint256) {
        return _taxSwapThreshold;
    }

    /**
     * Returns true if an address is excluded from taxes.
     * @param account The address to ckeck.
     */
    function excludedFromTaxes(address account) public view returns (bool) {
        return _excludedFromTaxes[account];
    }

    /**
     * Returns true if an address is a pair address.
     * @param account The address to ckeck.
     */
    function pair(address account) public view returns (bool) {
        return _pair[account];
    }

    /**
     * 返回一个地址的 代币余额.
     * @param account The address to ckeck.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _supplyOwned[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * 更新资管团队收税地址.
     * @param assetManagementTaxAddress The new assetManagement tax address.
     */
    function setAssetManagementTaxAddress(address assetManagementTaxAddress)
        public
        onlyOwner
    {
        address _oldAssetManagementTaxAddress = _assetManagementTaxAddress;

        includeInTaxes(_oldAssetManagementTaxAddress);

        excludeFromTaxes(assetManagementTaxAddress);

        _assetManagementTaxAddress = assetManagementTaxAddress;

        emit AssetManagementTaxAddressChange(
            _oldAssetManagementTaxAddress,
            _assetManagementTaxAddress
        );
    }

    /**
     * 更新营销收税地址.
     * @param marketingTaxAddress The new marketing tax address.
     */
    function setMarketingTaxAddress(address marketingTaxAddress)
        public
        onlyOwner
    {
        address _oldMarketingTaxAddress = _marketingTaxAddress;

        includeInTaxes(_oldMarketingTaxAddress);

        excludeFromTaxes(marketingTaxAddress);

        _marketingTaxAddress = marketingTaxAddress;

        emit MarketingTaxAddressChange(
            _oldMarketingTaxAddress,
            _marketingTaxAddress
        );
    }

    /**
     * 更新质押池税收地址
     * @param pledgePoolTaxAddress The new team tax address.
     */
    function setPledgePoolTaxAddress(address pledgePoolTaxAddress)
        public
        onlyOwner
    {
        address _oldPledgePoolTaxAddress = _pledgePoolTaxAddress;

        includeInTaxes(_oldPledgePoolTaxAddress);

        excludeFromTaxes(pledgePoolTaxAddress);

        _pledgePoolTaxAddress = pledgePoolTaxAddress;

        emit PledgePoolTaxTaxAddressChange(
            _oldPledgePoolTaxAddress,
            _pledgePoolTaxAddress
        );
    }

    /**
     * 更新税收。 确保总税额不超过 10%。
     * @param assetManagementTax_ The new assetManagementTax value.
     * @param marketingTax_ The new marketingTax value.
     * @param pledgePoolTax_ The new pledgePoolTax value.
     */
    function setTaxes(
        uint256 assetManagementTax_,
        uint256 marketingTax_,
        uint256 pledgePoolTax_
    ) public onlyOwner {
        require(
            assetManagementTax_ + marketingTax_ + pledgePoolTax_ <= 10,
            "Total taxes should never be more than 10%."
        );

        _assetManagementTax = assetManagementTax_;
        _marketingTax = marketingTax_;
        _pledgePoolTax = pledgePoolTax_;

        emit TaxesChange(_assetManagementTax, _marketingTax, _pledgePoolTax);
    }

    /**
     * 在税收中包含地址。
     * @param account The address to be included in taxes.
     */
    function includeInTaxes(address account) public onlyOwner {
        if (!_excludedFromTaxes[account]) return;
        _excludedFromTaxes[account] = false;

        // 发送事件
        emit IncludeInTaxes(account);
    }

    /**
     * 从税收中排除地址。
     * @param account The address to be excluded from taxes.
     */
    function excludeFromTaxes(address account) public onlyOwner {
        if (_excludedFromTaxes[account]) return;
        _excludedFromTaxes[account] = true;

        emit ExcludeFromTaxes(account);
    }

    /**
     * 启用总量 2% 每次转帐金额最大限制。
     */
    function enableTransferLimit() public onlyOwner {
        require(
            _maxTransferLimit == _totalSupply,
            "Transfer limit already enabled"
        );

        // 限制最大转帐金额为总量的0.2%
        _maxTransferLimit = SafeMath.div(_totalSupply, 500);

        // 发送事件
        emit EnableTransferLimit(_maxTransferLimit);
    }

    /**
     * 禁用总量 2% 的转账金额限制。
     */
    function disableTransferLimit() public onlyOwner {
        require(
            _maxTransferLimit != _totalSupply,
            "Transfer limit already disabled"
        );

        // 将最大转帐限制为总发行量
        _maxTransferLimit = _totalSupply;

        // 发送事件
        emit DisableTransferLimit(_maxTransferLimit);
    }

    /**
     * 用于存储 swap 交易地址
     * @param pairAddress The new pair address to be added.
     */
    function addPair(address pairAddress) public onlyOwner {
        _pair[pairAddress] = true;
        // 发送事件
        emit AddPair(pairAddress);
    }

    /**
     * 更新交换ETH时的点位，单位是wei
     * @param threshold The new tax swap threshold.
     */
    function setTaxSwapThreshold(uint256 threshold) public onlyOwner {
        _taxSwapThreshold = threshold;

        // 发送事件
        emit TaxSwapThresholdChange(_taxSwapThreshold);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 senderBalance = balanceOf(sender);
        require(
            senderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );

        // 如果在交换中， 返回
        if (_inSwap) return _swapTransfer(sender, recipient, amount);

        // 如果是 swap 路由配对地址，进行交换
        if (_pair[recipient]) _swapTaxes();

        uint256 afterTaxAmount = amount;

        // 只有在不排除发送者和接收者的情况下才征税
        // 如果其中之一是流动资金池地址。
        if (
            !_excludedFromTaxes[sender] &&
            !_excludedFromTaxes[recipient] &&
            (!_pair[sender] && !_pair[recipient])
        ) {
            // 判断是否超出最大转帐限制
            require(
                amount <= _maxTransferLimit,
                "Transfer amount exceeds max transfer limit"
            );
            // 减掉税之后的数量，奖励部分数量，排除掉数量(营销+团队)
            (afterTaxAmount) = _takeTaxes(amount);
        }

        _supplyOwned[sender] = SafeMath.sub(
            _supplyOwned[sender],
            afterTaxAmount
        );
        // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
        // decrementing then incrementing.
        _supplyOwned[recipient] = SafeMath.add(
            _supplyOwned[recipient],
            afterTaxAmount
        );

        // 发送事件
        emit Transfer(sender, recipient, afterTaxAmount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    // function _spendAllowance(
    //     address owner,
    //     address spender,
    //     uint256 amount
    // ) internal virtual {
    //     uint256 currentAllowance = allowance(owner, spender);
    //     if (currentAllowance != type(uint256).max) {
    //         require(
    //             currentAllowance >= amount,
    //             "ERC20: insufficient allowance"
    //         );
    //         unchecked {
    //             _approve(owner, spender, currentAllowance - amount);
    //         }
    //     }
    // }

    /**
     * _transfer 的轻量级版本。 仅在税收交换期间使用以保持gas fees low.
     */
    function _swapTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        _supplyOwned[sender] = SafeMath.sub(_supplyOwned[sender], amount);
        _supplyOwned[recipient] = SafeMath.add(_supplyOwned[recipient], amount);

        emit Transfer(sender, recipient, amount);
    }

    /**
     * 将累积的资管、营销、质押池税转出到对应的钱包和相应金额。
     */
    function transferTaxes() public onlyOwner {
        // 获取当前合约地址余额
        uint256 contractBalance = balanceOf(address(this));
        // 资管可兑换数量
        uint256 assetManagementAmount = SafeMath.div(
            (
                SafeMath.mul(
                    SafeMath.mul(contractBalance, 10),
                    _assetManagementTax
                )
            ),
            100
        );
        // 营销可兑换数量
        uint256 marketingAmount = SafeMath.div(
            (SafeMath.mul(SafeMath.mul(contractBalance, 10), _marketingTax)),
            100
        );

        // 质押池可兑换数量
        uint256 pledgePoolAmount = SafeMath.div(
            (SafeMath.mul(SafeMath.mul(contractBalance, 10), _pledgePoolTax)),
            100
        );

        // 批准 路由交换 可用数量
        _approve(
            address(this),
            _assetManagementTaxAddress,
            assetManagementAmount
        );
        _approve(address(this), _marketingTaxAddress, marketingAmount);
        _approve(address(this), _pledgePoolTaxAddress, pledgePoolAmount);

        // 对合约余额做减法
        _supplyOwned[address(this)] = SafeMath.sub(
            SafeMath.sub(
                SafeMath.sub(contractBalance, assetManagementAmount),
                marketingAmount
            ),
            pledgePoolAmount
        );

        // 对3个地址余额累加
        _supplyOwned[_assetManagementTaxAddress] = SafeMath.add(
            _supplyOwned[_assetManagementTaxAddress],
            assetManagementAmount
        );
        _supplyOwned[_marketingTaxAddress] = SafeMath.add(
            _supplyOwned[_marketingTaxAddress],
            marketingAmount
        );
        _supplyOwned[_pledgePoolTaxAddress] = SafeMath.add(
            _supplyOwned[_pledgePoolTaxAddress],
            pledgePoolAmount
        );
    }

    /**
     * 将累积的资管、营销、质押池税交换为 ETH 并发送到对应的钱包和相应金额。
     */
    function _swapTaxes() internal swapLock {
        // 获取当前合约地址余额
        uint256 contractBalance = balanceOf(address(this));

        // 如果余额 小于 swap的点位要求 或者 (奖励比例为0 并且 营销奖励为0) 返回
        if (
            contractBalance < _taxSwapThreshold ||
            (_assetManagementTax == 0 && _marketingTax == 0)
        ) return;

        // 批准 路由交换 可用数量
        _approve(address(this), address(_router), contractBalance);

        // 资管可兑换数量
        uint256 assetManagementAmount = SafeMath.div(
            (
                SafeMath.mul(
                    SafeMath.mul(contractBalance, 10),
                    _assetManagementTax
                )
            ),
            100
        );
        // 营销可兑换数量
        uint256 marketingAmount = SafeMath.div(
            (SafeMath.mul(SafeMath.mul(contractBalance, 10), _marketingTax)),
            100
        );

        // 质押池可兑换数量
        uint256 pledgePoolAmount = SafeMath.div(
            (SafeMath.mul(SafeMath.mul(contractBalance, 10), _pledgePoolTax)),
            100
        );

        // 获取路由地址
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _router.WETH();

        // 资管部分 兑换成 ETH
        // 沿着路径确定的路线，用尽可能多的 ETH 交换准确数量的代币
        _router.swapExactTokensForETH(
            assetManagementAmount,
            0,
            path,
            _assetManagementTaxAddress,
            block.timestamp
        );

        // 营销部分 兑换成 ETH
        _router.swapExactTokensForETH(
            marketingAmount,
            0,
            path,
            _marketingTaxAddress,
            block.timestamp
        );

        // 质押池部分 兑换成 ETH
        _router.swapExactTokensForETH(
            pledgePoolAmount,
            0,
            path,
            _pledgePoolTaxAddress,
            block.timestamp
        );
    }

    /**
     * 计算税额并将其分配给合约
     * @param amount The amount to take taxes from.
     */
    function _takeTaxes(uint256 amount) internal returns (uint256) {
        // 计算资管部分数量
        uint256 assetManagementTaxAmount = SafeMath.div(
            SafeMath.mul(amount, _assetManagementTax),
            100
        );

        // 计算营销部分数量
        uint256 marketingTaxAmount = SafeMath.div(
            SafeMath.mul(amount, _marketingTax),
            100
        );

        // 计算质押部分数量
        uint256 pledgePoolTaxAmount = SafeMath.div(
            SafeMath.mul(amount, _pledgePoolTax),
            100
        );

        // 减掉税之后的数量
        uint256 afterTaxAmount = SafeMath.sub(
            SafeMath.sub(
                SafeMath.sub(amount, assetManagementTaxAmount),
                marketingTaxAmount
            ),
            pledgePoolTaxAmount
        );

        // 当前合约数量 += 营销分配 + 质押池分配 + 资管团队分配
        _supplyOwned[address(this)] = SafeMath.add(
            _supplyOwned[address(this)],
            SafeMath.add(
                SafeMath.add(marketingTaxAmount, pledgePoolTaxAmount),
                assetManagementTaxAmount
            )
        );

        return (afterTaxAmount);
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        returns (bool)
    {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }
}

