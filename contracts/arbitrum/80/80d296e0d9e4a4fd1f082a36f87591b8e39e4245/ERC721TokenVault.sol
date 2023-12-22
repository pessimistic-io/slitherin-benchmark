//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC721.sol";
import "./ERC20.sol";
import "./ERC20Upgradeable.sol";
import "./ERC721HolderUpgradeable.sol";
import "./IUniswapV2Pair.sol";

contract ERC721TokenVault is ERC20Upgradeable, ERC721HolderUpgradeable {
    using Address for address;

    // address public constant usdc = 0x07865c6E87B9F70255377e024ace6630C1Eaa37F;
    address public usdc;

    address public token; // 721

    uint256 public token_id;

    address public curator;

    uint256 public dividendPerToken;

    uint256 public pricePerToken;

    uint256 public currSupply;

    uint256 public maxSupply;

    uint256 public fundsFromTokenPurchases;

    mapping(address => uint256) dividendBalanceOf;
    mapping(address => uint256) dividendPerTokenCreditedTo;

    event FundsReceived(uint256 value, uint256 dividendPerToken);
    event Calculated(address addr, uint256 newAmount);
    event USDC(uint256 amt);

    address public LPToken;
    address public pool;
    uint256 public dividendPerToken_LP;
    uint256 public totalSupply_LP;

    mapping(address => uint256) balanceOf_LP;
    mapping(address => uint256) dividendPerTokenCreditedTo_LP;
    mapping(address => uint256) dividendBalanceOf_LP;


    function initialize(address _curator, address _token, uint256 _id, uint256 _supply, string memory _name, string memory _symbol, uint256 _pricePerToken) external initializer {        
        __ERC20_init(_name, _symbol);
        __ERC721Holder_init();

        token = _token;
        token_id = _id;
        pricePerToken = _pricePerToken;

        currSupply = 0;
        maxSupply = _supply;

        // _mint(address(this), _supply);

        dividendPerToken = 0;
        fundsFromTokenPurchases = 0;

        usdc = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

        curator = _curator;
    }

    function transfer(address to, uint256 value) public override returns (bool success) {
        require(balanceOf(msg.sender) >= 0);

        update(msg.sender);
        update(to);

        return super.transfer(to, value);
    }

    function update(address account) internal {
        uint256 owed = dividendPerToken - dividendPerTokenCreditedTo[account];
        emit Calculated(account, ((balanceOf(account) * owed) / 10**18));
        dividendBalanceOf[account] += ((balanceOf(account) * owed) / 10**18);
        dividendPerTokenCreditedTo[account] = dividendPerToken;
    }

    function updateCurator(address _newCurrator) external {
        require(msg.sender == curator);

        curator = _newCurrator;
    }

    /*
    fallback() external payable {
        dividendPerToken += msg.value / (totalSupply() / (10**18));  // ignoring the remainder
        emit FundsReceived(msg.value, dividendPerToken);
    }

    receive() external payable {
        dividendPerToken += msg.value / (totalSupply() / (10**18));  // ignoring the remainder
        emit FundsReceived(msg.value, dividendPerToken);
    }
    */

    function curatorPayUSDC(uint256 num) external {
        bool success = ERC20(usdc).transferFrom(msg.sender, address(this), num);
        require(success, "Could not transfer token. Missing approval?");
        // calculate how much goes to liquidity providers and how much to regular users
        uint256 amountInPool = balanceOf(pool);

        // amount for LPs: (amountInPool / totalSupply()) * num
        //                 (2 * 10^18     / 200 * 10^18)  * 10 * 10^6
        // amount for token holder dividends: ((totalSupply() - amountInPool) / totalSupply()) * num
        //                                    ((200 * 10^18   - 2 * 10^18   ) / 200 * 10^18  ) * 10 * 10^6
        
        // dividendPerToken += 10**18 * ((totalSupply() - amountInPool) * num * 10**18 / ((totalSupply() - amountInPool) * totalSupply()));
        dividendPerToken += (num * 10**36) / (totalSupply());  // ignoring the remainder

        dividendPerToken_LP += 10**18 * ((num * amountInPool * 10**18) / (totalSupply() * totalSupply_LP));

        emit FundsReceived(num, dividendPerToken);
    }

    function purchaseTokensUSDC(uint256 num) external {
        require(num + totalSupply() <= maxSupply, "Exceeded supply");
        // maxSupply is 100 * 10**18
        fundsFromTokenPurchases += (num * pricePerToken) / 10**18;
        emit USDC((num * pricePerToken) / 10**18);
        bool success = ERC20(usdc).transferFrom(msg.sender, address(this), (num * pricePerToken) / 10**18);
        require(success, "Could not transfer token. Missing approval?");
        _mint(msg.sender, num);
    }

    function withdrawDividend() public {
        update(msg.sender);
        uint256 amount = dividendBalanceOf[msg.sender] / 10**18;
        dividendBalanceOf[msg.sender] = 0;
        bool success = ERC20(usdc).transfer(msg.sender, amount);
        require(success, "Could not transfer token. Missing approval?");
    }

    function withdrawUSDC() public {
        require(msg.sender == curator);
        uint256 amount = fundsFromTokenPurchases;
        fundsFromTokenPurchases = 0;
        bool success = ERC20(usdc).transfer(curator, amount);
        require(success, "withdrawUSDC failed");
    }

    function withdrawDividend_LP() public {
        update_LP(msg.sender);
        uint256 amount = dividendBalanceOf_LP[msg.sender] / 10**18;
        dividendBalanceOf_LP[msg.sender] = 0;
        bool success = ERC20(usdc).transfer(msg.sender, amount);
        require(success, "Could not transfer token. Missing approval?");
    }

    function update_LP(address account) internal {
        uint256 owed = dividendPerToken_LP - dividendPerTokenCreditedTo_LP[account];
        emit Calculated(account, ((balanceOf_LP[account] * owed) / 10**18));
        dividendBalanceOf_LP[account] += ((balanceOf_LP[account] * owed) / 10**18);
        dividendPerTokenCreditedTo_LP[account] = dividendPerToken_LP;
    }

    function withdrawNFT() public {
        require(curator == msg.sender);
        IERC721(token).safeTransferFrom(address(this), msg.sender, token_id);
    }

    function setMaxSupply(uint256 _maxSupply) public {
        require(curator == msg.sender);
        maxSupply = _maxSupply;
    }

    function setTokenPrice(uint256 _pricePerToken) public {
        require(curator == msg.sender);
        pricePerToken = _pricePerToken;
    }

    function setLPToken(address _lpToken) public {
        require(curator == msg.sender);
        LPToken = _lpToken;
    }

    function depositLPToken(uint256 _amount) public {
        update_LP(msg.sender);
        bool success = ERC20(LPToken).transferFrom(msg.sender, address(this), _amount);
        require(success, "Could not transfer token. Missing approval?");
        balanceOf_LP[msg.sender] += _amount;
        totalSupply_LP += _amount;
    }

    function withdrawLPToken(uint256 _amount) public {
        require(balanceOf_LP[msg.sender] >= _amount);
        update_LP(msg.sender);
        balanceOf_LP[msg.sender] -= _amount;
        totalSupply_LP -= _amount;
        ERC20(LPToken).transfer(msg.sender, _amount);
    }
}
