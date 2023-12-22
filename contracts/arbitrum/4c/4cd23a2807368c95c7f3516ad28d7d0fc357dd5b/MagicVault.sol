//SPDX-License-Identifier: Unlicense
// Creator: Pixel8 Labs
pragma solidity ^0.8.7;

import "./Signature.sol";
import "./IProvider.sol";
import "./ERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./ContextUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ERC20_IERC20.sol";
import "./SafeMath.sol";

contract MagicVault is Initializable, ContextUpgradeable, ERC20Upgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeMath for uint256;

    receive() external payable{}
    fallback() external payable{}

    // @notice Constants used in this contract
    uint256 constant MAX_INT = 2 ** 256 - 1;

    // @notice Signer address
    address public signer;

    // @notice USDC token interface
    IERC20 public magic;
    IERC20 public usdc;

    // @notice maximum amount of tokens that can be deposited
    uint256 public maxDepositFee;

    // @notice Provider contract interface
    mapping(address => IProvider) public adapter;
    address public currentProvider;

    // Custom Errors
    error DepositLimitReached();
    error ZeroDepositAmount();
    error ZeroWithdrawAmount();
    error InvalidSignature();
    error NotEnoughBalance();

    // Events
    event LPTokenMinted(address _to, uint256 _amount);
    event USDCwithdraw(address _to, uint256 _mvlpToken, uint256 _usdc);
    event MAGICCollect(address _to, uint256 _magic);
    event Settle(address _to, uint256 _amount, uint256 _usdc, string _providerName);

    function initialize (
        address _magicAddress,
        address _usdcAddress,
        address _signerAddress,
        address _stgAdapterAddress,
        address _synAdapterAddress
    ) initializer nonReentrant() public {
        __ERC20_init("Magic Vault LP Token", "MV-LP");
        __Context_init();
        __ReentrancyGuard_init();
        __Ownable_init();
        // Setup Magic Interface 
        magic = IERC20(_magicAddress);
        
        // Setup USDC Interface
        usdc = IERC20(_usdcAddress);

        // Setup Signer Address
        signer = _signerAddress;

        // Setup Provider Interface & Current Provider
        adapter[_stgAdapterAddress] = IProvider(_stgAdapterAddress);
        adapter[_synAdapterAddress] = IProvider(_synAdapterAddress);
        currentProvider = _stgAdapterAddress;  

        // Setup Max Deposit Fee
        maxDepositFee = 100000*10**6; // 100,000 USDC

        // Approve USDC to be spent by adapter
        usdc.approve(_stgAdapterAddress, MAX_INT);
        usdc.approve(_synAdapterAddress, MAX_INT);
    }

    // @notice MV-LP token will use 6 decimals (stablecoin decimals)
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function deposit(uint256 _amountUSDC) external nonReentrant {
        IProvider provider = adapter[currentProvider];
        if (_amountUSDC == 0) revert ZeroDepositAmount();     
        if (_amountUSDC.add(provider.currentDepositFee()) > maxDepositFee && maxDepositFee != 0) revert DepositLimitReached();

        // Transfer USDC from user to contract
        usdc.transferFrom(msg.sender, address(this), _amountUSDC);

        // Deposit USDC to Adapter Provider
        provider.stake(address(this), _amountUSDC);

        // Mint MV-LP token
        _mint(msg.sender, _amountUSDC);
        emit LPTokenMinted(msg.sender, _amountUSDC);
    }

    function withdraw(uint256 _amountMVLpToken) external nonReentrant {
        IProvider provider = adapter[currentProvider];
        if(_amountMVLpToken == 0) revert ZeroWithdrawAmount();
        if(_amountMVLpToken > balanceOf(msg.sender)) revert NotEnoughBalance();

        // Share of user's MVLP token
        uint256 share = (_amountMVLpToken.mul(1e6)).div(totalSupply());

        // Withdraw USDC from Adapter Provider
        uint256 usdcAmount = provider.unstake(msg.sender, share);

        // Burn MV-LP token
        _burn(msg.sender, _amountMVLpToken);

        emit USDCwithdraw(msg.sender, _amountMVLpToken, usdcAmount);
    }

    function claim(uint256 _amountMAGIC, bytes memory signature) external nonReentrant {
        if(_amountMAGIC == 0) revert ZeroWithdrawAmount();
        
        // Verify signature
        if(Signature.verify(_amountMAGIC, msg.sender, signature) != signer) revert InvalidSignature();
        
        // Transfer $MAGIC from contract to user
        magic.transfer(msg.sender, _amountMAGIC);
        emit MAGICCollect(msg.sender, _amountMAGIC);
    }

    function withdrawERC20(address _erc20) external nonReentrant onlyOwner {
        IERC20 token = IERC20(_erc20);

        // Transfer all the tokens to owner
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function withdrawERC20Adapter(address _erc20, address _provider) external nonReentrant onlyOwner {
        IProvider provider = adapter[_provider];
        IERC20 token = IERC20(_erc20);

        // Take all the tokens from provider
        provider.withdrawERC20(_erc20, address(this));

        // Transfer all the tokens to owner
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function withdrawETH() external payable nonReentrant onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "MagicVault: ETH_TRANSFER_FAILED");
    }

    function withdrawETHAdapter(address _provider) external payable nonReentrant onlyOwner {
        IProvider provider = adapter[_provider];

        // Take all the ETH from provider
        provider.withdrawETH(address(this));

        // Transfer all the ETH to owner
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success, "MagicVault: ETH_TRANSFER_FAILED");
    }

    function settle() external nonReentrant onlyOwner {
        IProvider provider = adapter[currentProvider];
        (uint256 amount, uint256 usdcAmount, string memory providerName) = provider.claim(address(this));
        emit Settle(msg.sender, amount, usdcAmount, providerName);
    }

    function setSignerAddress(address _signer) external onlyOwner {
        signer = _signer;
    }

    function setMaxDepositFee(uint256 _maxDepositFee) external onlyOwner {
        maxDepositFee = _maxDepositFee;
    }

    function addProvider(address _providerAddress) external onlyOwner {
        adapter[_providerAddress] = IProvider(_providerAddress);
        usdc.approve(_providerAddress, MAX_INT);
    }

    function setProvider(address _providerAddress) external onlyOwner {
        IProvider oldProvider = adapter[currentProvider];
        IProvider newProvider = adapter[_providerAddress];

        // Get MVLP Total Supply
        uint256 totalSupply = totalSupply();

        // When there are still MVLP token
        // move all USDC and stake USDC to new provider
        if(totalSupply > 0){
            uint256 usdcAmount = oldProvider.migrate(_providerAddress);
            newProvider.stakeByAdapter(usdcAmount);
        }

        // Set new provider
        currentProvider = _providerAddress;
    }
}
