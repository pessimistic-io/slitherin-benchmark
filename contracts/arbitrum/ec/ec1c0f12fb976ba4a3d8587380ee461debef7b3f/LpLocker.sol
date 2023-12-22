// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./ERC721.sol";
import "./Ownable.sol";
import "./IUniswapV3Pool.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";

contract LpLocker is ERC721,Ownable, ReentrancyGuard {
     
    
    
    event Deposit(address indexed user, uint256 FUC_Amount, uint256 WETH_Amount, uint256 lockPeriod);
    event Withdraw(address indexed user, uint256 FUC_Amount, uint256 WETH_Amount);
    event FundManagerSet(address indexed oldFundManager, address indexed newFundManager);

    struct NFTData {
        uint256 fucDeposit;
        uint256 wethDeposit;
        address currentOwner;
        uint256 depositTimestamp;
        uint256 lockPeriod;
    }

    mapping(address => uint256[]) public ownerToTokenIds;
    mapping(uint256 => uint256) public tokenIdToIndex;




    mapping(uint256 => NFTData) public nftData;
    uint256 public currentTokenId = 0;
    IERC20 public FUC;
    IERC20 public WETH;
    IUniswapV3Pool public pool;
    address public fundManager;

    constructor(
        address _FUC,
        address _WETH,
        address _pool,
        address _fundManager
    ) ERC721("LpLocker", "LL") {
        require(_FUC != address(0), "FUC address cannot be zero");
        require(_WETH != address(0), "WETH address cannot be zero");
        require(_pool != address(0), "Pool address cannot be zero");
        require(_fundManager != address(0), "FundManager address cannot be zero");

        FUC = IERC20(_FUC);
        WETH = IERC20(_WETH);
        pool = IUniswapV3Pool(_pool);
        fundManager = _fundManager;
    }

    function getTokenIds(address owner) public view returns (uint256[] memory) {
        return ownerToTokenIds[owner];
    }
    
    function safeMint(address to, uint256 tokenId) public onlyOwner {
        _safeMint(to, tokenId);
    }
    
    function getNFTData(uint256 tokenId) public view returns (NFTData memory) {
        return nftData[tokenId];
    }
    
    function getTokenIdsByOwner(address owner) public view returns (uint256[] memory) {
        return ownerToTokenIds[owner];
    }

    
    function mintPosition(uint256 FUC_Amount, uint256 WETH_Amount, uint8 lockPeriodIndex) public nonReentrant {
        require(FUC_Amount > 1e20, "FUC_Amount must be greater than 0.1"); // 100 FUC
        require(WETH_Amount > 1e15, "WETH_Amount must be greater than 0.001"); // 0.001 WETH
        require(lockPeriodIndex < 3, "Invalid lock period index");
    
        uint256[] memory lockPeriods = new uint256[](3);
        lockPeriods[0] = 90 days;
        lockPeriods[1] = 180 days;
        lockPeriods[2] = 360 days;

        
        uint256 lockPeriod = lockPeriods[lockPeriodIndex];

        /*
        IUniswapV3Pool uniswapPool = IUniswapV3Pool(pool);
        (uint160 sqrtPriceX96,,,,,,) = uniswapPool.slot0();
        uint256 poolRatio = SafeMath.div(SafeMath.mul(uint256(sqrtPriceX96), uint256(sqrtPriceX96)), (1 << 96));
        uint256 depositRatio = SafeMath.div(FUC_Amount, WETH_Amount);
        
        require(depositRatio * 10 / 8 <= poolRatio && depositRatio * 10 / 12 >= poolRatio, "Deposit ratio must be within 20% of the pool ratio");
        */

        
        // Check allowance
        require(IERC20(FUC).allowance(msg.sender, address(this)) >= FUC_Amount, "Not enough FUC allowance");
        require(IERC20(WETH).allowance(msg.sender, address(this)) >= WETH_Amount, "Not enough WETH allowance");
        
        // Check balance of FUC and WETH
        require(IERC20(FUC).balanceOf(msg.sender) >= FUC_Amount, "Not enough FUC tokens");
        require(IERC20(WETH).balanceOf(msg.sender) >= WETH_Amount, "Not enough WETH tokens");

        
        // Transfer
        require(IERC20(FUC).transferFrom(msg.sender, address(this), FUC_Amount), "FUC transfer failed");
        require(IERC20(WETH).transferFrom(msg.sender, address(this), WETH_Amount), "WETH transfer failed");
        
        // Emit Deposite Event
        emit Deposit(msg.sender, FUC_Amount, WETH_Amount, lockPeriod);
        // Mint NFT 
        nftData[currentTokenId] = NFTData({
            fucDeposit:  FUC_Amount,
            wethDeposit: WETH_Amount,
            currentOwner: msg.sender,
            depositTimestamp: block.timestamp,
            lockPeriod:lockPeriod
        });

        // Check that the update was successful
        require(nftData[currentTokenId].currentOwner == msg.sender, "Failed to update nftData array");

        _mint(msg.sender, currentTokenId);

        // Check that the minting was successful
        require(ownerOf(currentTokenId) == msg.sender, "Failed to mint NFT");

        // Add the token ID to the array of the owner
        ownerToTokenIds[msg.sender].push(currentTokenId);

        // Update the mapping with the new index of the token ID in the array
        tokenIdToIndex[currentTokenId] = ownerToTokenIds[msg.sender].length - 1;

        // Check that the update was successful
        require(tokenIdToIndex[currentTokenId] == ownerToTokenIds[msg.sender].length - 1, "Failed to update tokenIdToIndex mapping");

        currentTokenId++;
    }
 
    function withdraw(uint256 FUC_Amount, uint256 WETH_Amount) public nonReentrant {
        require(msg.sender == fundManager, "Only the fund manager can withdraw tokens");

        uint256 contractFUCBalance = IERC20(FUC).balanceOf(address(this));
        uint256 contractWETHBalance = IERC20(WETH).balanceOf(address(this));

        require(FUC_Amount <= contractFUCBalance, "Not enough FUC tokens in the contract");
        require(WETH_Amount <= contractWETHBalance, "Not enough WETH tokens in the contract");

        require(IERC20(FUC).transfer(fundManager, FUC_Amount), "FUC transfer failed");
        require(IERC20(WETH).transfer(fundManager, WETH_Amount), "WETH transfer failed");

        emit Withdraw(fundManager, FUC_Amount, WETH_Amount);
    }


    function withdrawFUC(uint256 FUC_Amount) public nonReentrant {
        require(msg.sender == fundManager, "Only the fund manager can withdraw tokens");
        uint256 contractFUCBalance = IERC20(FUC).balanceOf(address(this));
        require(FUC_Amount <= contractFUCBalance, "Not enough FUC tokens in the contract");
        require(IERC20(FUC).transfer(fundManager, FUC_Amount), "FUC transfer failed");
        emit Withdraw(fundManager, FUC_Amount, 0);



    }

    function withdrawWETH(uint256 WETH_Amount) public nonReentrant {
        require(msg.sender == fundManager, "Only the fund manager can withdraw tokens");
        uint256 contractWETHBalance = IERC20(WETH).balanceOf(address(this));
        require(WETH_Amount <= contractWETHBalance, "Not enough WETH tokens in the contract");
        require(IERC20(WETH).transfer(fundManager, WETH_Amount), "WETH transfer failed");
        emit Withdraw(fundManager, 0, WETH_Amount);
    }


    function setFundManager(address _fundManager) public onlyOwner {
        emit FundManagerSet(fundManager, _fundManager);
        fundManager = _fundManager;
    }

     


    

    function redeem(uint256 tokenId) public  nonReentrant {

        
        // Ensure the caller owns the token that is being redeemed
        require(_isApprovedOrOwner(msg.sender, tokenId), "Caller is not owner nor approved");

        // Get the NFTData for the token
        NFTData memory data = nftData[tokenId];

        // Ensure the token has not already been redeemed
        require(nftData[tokenId].depositTimestamp != 0, "Token has already been redeemed");
        
        // Ensure the lock period has passed
        require(block.timestamp >= data.depositTimestamp + data.lockPeriod, "Lock period has not passed");

        // Ge the current balance of WETH and FUC in the contract
        uint256 contractFUCBalance = IERC20(FUC).balanceOf(address(this));
        uint256 contractWETHBalance = IERC20(WETH).balanceOf(address(this));

        // Ensure the contract has enought balance
        require(data.fucDeposit <= contractFUCBalance, "Not enough FUC tokens in the contract");
        require(data.wethDeposit <= contractWETHBalance, "Not enough WETH tokens in the contract");


        // Transfer the NFT to the contract
        // This will fail if the caller is not the owner or an approved operator
        _transfer(msg.sender, address(this), tokenId);

        // Transfer the FUC and WETH tokens to the caller
        require(IERC20(FUC).transfer(msg.sender, data.fucDeposit), "FUC transfer failed");
        require(IERC20(WETH).transfer(msg.sender, data.wethDeposit), "WETH transfer failed");

        emit Withdraw(msg.sender, data.fucDeposit, data.wethDeposit);
       
    }


    /* Gas efficiency Improvement 
    function _transfer(address from, address to, uint256 tokenId) internal override {
        super._transfer(from, to, tokenId);

        // Remove tokenId from the list of the sender
        uint256 lastTokenIndex = ownerToTokenIds[from].length - 1;
        uint256 lastTokenId = ownerToTokenIds[from][lastTokenIndex];

        for (uint256 i = 0; i < ownerToTokenIds[from].length; i++) {
            if (ownerToTokenIds[from][i] == tokenId) {
                ownerToTokenIds[from][i] = lastTokenId;
                ownerToTokenIds[from].pop();
                break;
            }
        }

        // Add tokenId to the list of the receiver
        ownerToTokenIds[to].push(tokenId);
        // Update nftData to reflect the current owner
        nftData[tokenId].currentOwner = to;
    }   
    */
    function _transfer(address from, address to, uint256 tokenId) internal override {
        super._transfer(from, to, tokenId);

        // Get the index of the token ID in the array
        uint256 index = tokenIdToIndex[tokenId];

        // Remove the token ID from the array
        uint256 lastTokenIndex = ownerToTokenIds[from].length - 1;
        uint256 lastTokenId = ownerToTokenIds[from][lastTokenIndex];
        ownerToTokenIds[from][index] = lastTokenId;
        ownerToTokenIds[from].pop();

        // Update the mapping
        tokenIdToIndex[lastTokenId] = index;

        // Add the token ID to the array of the new owner
        ownerToTokenIds[to].push(tokenId);
        tokenIdToIndex[tokenId] = ownerToTokenIds[to].length - 1;

        // Update nftData to reflect the current owner
        nftData[tokenId].currentOwner = to;
    }

    function _burn(uint256 tokenId) internal override {
        super._burn(tokenId);

        address owner = ownerOf(tokenId);

        // Remove tokenId from the list of the owner
        uint256 lastTokenIndex = ownerToTokenIds[owner].length - 1;
        uint256 lastTokenId = ownerToTokenIds[owner][lastTokenIndex];

        for (uint256 i = 0; i < ownerToTokenIds[owner].length; i++) {
            if (ownerToTokenIds[owner][i] == tokenId) {
                ownerToTokenIds[owner][i] = lastTokenId;
                ownerToTokenIds[owner].pop();
                break;
            }
        }
    }


}

