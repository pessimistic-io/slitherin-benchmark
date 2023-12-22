// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IERC20.sol";

import "./OwnableUpgradeable.sol";


interface IRoyalties{
    function deposit(uint256 amount) external;
}
interface IWETH{
     function deposit() external payable ;
}

interface IStakingNFTConverter {
    function claimFees() external;
    function swap() external;
}

// The base pair of pools, either stable or volatile
contract NFTSalesSplitter is OwnableUpgradeable  {

    uint256 constant public PRECISION = 1000;
    uint256 constant public WEEK = 86400 * 7;
    uint256 public converterFee;
    uint256 public royaltiesFee;
    uint256 public teamFee;

    address public weth;
    
    address public stakingConverter;
    address public royalties;
    address public teamMS;


    mapping(address => bool) public splitter;


    event Split(uint256 indexed timestamp, uint256 toStake, uint256 toRoyalties, uint256 toTeamMS);
    
    modifier onlyAllowed() {
        require(msg.sender == owner() || splitter[msg.sender]);
        _;
    }

    constructor() {}

    function initialize() initializer  public {
        __Ownable_init();
        weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        stakingConverter = address(0x0000000000000000000000000000000000000000);
        royalties = address(0x0000000000000000000000000000000000000000);
        teamMS = address(0x345E50e9B192fB77eA2c789d9b486FD425441FdD);
        converterFee = 400;
        royaltiesFee = 400;
        teamFee = 200;
    }

    function swapWETHToETH() public onlyAllowed {
        _swapWETHToETH();
    }

    function _swapWETHToETH() internal {
        if(address(this).balance > 0){
            IWETH(weth).deposit{value: address(this).balance}();
        }
    }

    function split() public onlyAllowed {
        
        // convert eth to weth, easier to handle
        _swapWETHToETH();

        uint256 balance = balanceOf();
        uint256 stakingAmount = 0;
        uint256 royaltiesAmount = 0;
        uint256 teamAmount = 0;
        uint256 timestamp = block.timestamp / WEEK * WEEK;
        if(balance > 1000){
            if( stakingConverter != address(0) ){
                stakingAmount = balance * converterFee / PRECISION;
                IERC20(weth).transfer(stakingConverter, stakingAmount);
                IStakingNFTConverter(stakingConverter).claimFees();
                IStakingNFTConverter(stakingConverter).swap();
            }

            if( royalties != address(0) ){
                royaltiesAmount = balance * royaltiesFee / PRECISION;
                //check we have all, else send balanceOf
                if(balanceOf() < royaltiesAmount){
                    royaltiesAmount = balanceOf();
                }
                IERC20(weth).approve(royalties, 0);
                IERC20(weth).approve(royalties, royaltiesAmount);
                IRoyalties(royalties).deposit(royaltiesAmount);
            }

            if( teamMS != address(0) ){
                teamAmount = balance * teamFee / PRECISION;
                IERC20(weth).transfer(teamMS, teamAmount);
            }
            emit Split(timestamp, stakingAmount, royaltiesAmount, teamAmount);
        } else {
            emit Split(timestamp, 0, 0, 0);
        }    

    }

    function balanceOf() public view returns(uint){
        return IERC20(weth).balanceOf(address(this));
    }

    function setConverter(address _converter) external onlyOwner {
        require(_converter != address(0));
        stakingConverter = _converter;
    }

    function setRoyalties(address _royal) external onlyOwner {
        require(_royal != address(0));
        royalties = _royal;
    }

    function setSplitter(address _splitter, bool _what) external onlyOwner {
        splitter[_splitter] = _what;
    }

    
    ///@notice in case token get stuck.
    function withdrawERC20(address _token) external onlyOwner {
        require(_token != address(0));
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, _balance);
    }

    function setFees(uint256 _amountToStaking, uint256 _amountToRoyalties, uint256 _teamFees ) external onlyOwner {
        require(_amountToStaking + _amountToRoyalties + _teamFees <= PRECISION, 'too many');
        converterFee = _amountToStaking;
        royaltiesFee = _amountToRoyalties;
        teamFee = _teamFees;
    }

    receive() external payable {}

}
