// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./console.sol";
import "./Strings.sol";
import "./ERC721.sol";
import "./HeruCFANFTManagerTest.sol";
import "./Counters.sol";
//import "./gmx-contracts/contracts/core/PositionRouter.sol";

interface GLPInterface{
    function mintAndStakeGlp(address _token,uint256 _amount,uint256 _minUsdg,uint256 _minGlp) external;
}

interface GLPRouterInterface{
    function approvePlugin(address _plugin) external;
}

interface GLPPositionRouterInterface{
    function createIncreasePosition(address[1] calldata _path,address _indexToken,uint256 _amountIn,uint256 _minOut,uint256 _sizeDelta,bool _isLong,uint256 _acceptablePrice,uint256 _executionFee,bytes32 _referralCode,address _callbackTarget) external payable;
}

contract CashFutureArbitrage is Ownable{

    uint public version = 1;
    IERC20 public acceptedToken;
    mapping(address=>mapping(address=>uint256)) public balances;
    uint256 public shortBalance;
    event TokenReceived(address sender, uint256 amount, address acceptedToken);
    event AcceptedTokenChange(address prevAcceptedToken, address newAcceptedToken);
    HeruCFANFTManagerTest public nftManager;
    event ContractCreated(address newAddress);
    event NFTMinted(address owner,address nftAddress,uint256 tokenId);
    uint256 constant public MAX_INT = type(uint256).max;


    address public constant glpAddress=0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    address public constant glpManagerAddress=address(0x3963FfC9dff443c2A94f21b129D429891E32ec18);
    address public constant glpRouterAddress=0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064;
    address public constant glpPositionRouterAddress=0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868;
    GLPInterface glpContract = GLPInterface(glpAddress);
    GLPRouterInterface glpRouter = GLPRouterInterface(glpRouterAddress);
    GLPPositionRouterInterface glpPositionRouter=GLPPositionRouterInterface(glpPositionRouterAddress);

    constructor() {
        console.log('Deploying Version:', version);
        nftManager=new HeruCFANFTManagerTest(address(this));
        emit ContractCreated(address(nftManager));
    }
    function setAcceptedToken(address add) public onlyOwner{
        address old=address(acceptedToken);
        console.log(address(old));
        acceptedToken=IERC20(address(add));
        console.log(address(add));
        emit AcceptedTokenChange(old,add);
    }

    function setupGlpForOwner() public onlyOwner{
        approveGlpSpend(MAX_INT);
        //for enabling leverage
        enableGlpLeverage();
    }

    // calling context is contract, hence will provie approval to use accepted tokens OF the contract to be spent. 
    function approveToken() public onlyOwner{
        console.log("approveToken");
        console.log(address(acceptedToken));
        console.log(msg.sender);
        console.log(address(this));
        bool isApproved=acceptedToken.approve(msg.sender, 3 ether);
        console.log(isApproved);
        if(isApproved){
            console.log(acceptedToken.allowance(address(this),msg.sender));
        }else{
            revert("failed to approve");
        }
    }


    function receiveToken(uint256 amount) public onlyOwner{
        console.log(string.concat("in receiveToken", (Strings.toString(amount))));
        require(acceptedToken.allowance(msg.sender, address(this)) >= amount, "Amount not approved");
        balances[address(acceptedToken)][msg.sender]+=amount;
        shortBalance+=amount/3;
        acceptedToken.transferFrom(msg.sender, address(this), amount);
        uint256 tokenId=nftManager.mint(HeruCFANFTManagerTest.MintParams({depositor:msg.sender,amount:amount,futureAmount:amount/3}));
        console.log(nftManager.tokenURI(tokenId));
        //acceptedToken.transfer(msg.sender,amount/2);
        emit TokenReceived(msg.sender,amount,address(acceptedToken));
        emit NFTMinted(msg.sender,address(nftManager),tokenId);
        approveGlpSpend(3*amount);
        enableGlpLeverage();
        //buyGlpfromAmount(2*amount/3);
    }

    function enableGlpLeverage() public onlyOwner{
        glpRouter.approvePlugin(0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064);
    }

    function approveGlpSpend(uint256 amount) internal onlyOwner{
        //for buying glp
        acceptedToken.approve(glpAddress, amount);
        //for buying glp(actual)
        acceptedToken.approve(glpManagerAddress,amount);
        //for short trade
        acceptedToken.approve(glpRouterAddress,amount);
    }

    function buyGlpfromAmount(uint256 amount) public onlyOwner {
        console.log(amount);
        console.log(acceptedToken.allowance(address(this),glpAddress));
        console.log(acceptedToken.allowance(address(this),glpManagerAddress));
        //acceptedToken.approve(glpAddress, 3*amount);
        glpContract.mintAndStakeGlp(address(acceptedToken),amount,0,1);
    }

    function shortEthWithAmount(uint256 amount) public payable onlyOwner {
        address weth=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        console.log(amount);
        console.log(address(this).balance);
        console.log(acceptedToken.balanceOf(address(this)));
        glpPositionRouter.createIncreasePosition{value:100000000000000}([address(acceptedToken)], weth, amount, 0, 18960079840319360268800000000000, false, 1014944200000000000000000000000000, 100000000000000, 0x0000000000000000000000000000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000);
    }

    function returnAcceptedTokens() public onlyOwner{
        require(balances[address(acceptedToken)][msg.sender]>0,"need positive balance");
        /*console.log("allowance is");
        console.log(acceptedToken.allowance(address(this),msg.sender));
        approveToken();
        console.log("allowance is");
        console.log(acceptedToken.allowance(address(this),msg.sender));*/
        
        console.log("ether balance is");
        console.log(address(this).balance);
        
        uint256 amt=balances[address(acceptedToken)][msg.sender];
        balances[address(acceptedToken)][msg.sender]=0;
        shortBalance-=amt/3;
        console.log(Strings.toString(amt));
        acceptedToken.transfer(msg.sender,amt);
    }

    fallback () external payable {}
    receive() external payable {}
}

