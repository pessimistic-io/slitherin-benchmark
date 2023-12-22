//  Arbitrum Bitcoin and Staking - Auctions Contract
//  Auctions Arbitrum Bitcoin and Staking (ABAS) tokens every 12 days and users are able to withdraw anytime after!
//
//  The Ethereum collected by ABAS Auctions go to miners and liquidity providers!
//
//  10,500,000 ABAS tokens are Auctioned off over 100 years in this contract! In the first era ~5,000,000 are auctioned and half every era after!
//
//  Distributes 32,768 ABAS tokens every ~25 days for the first era(~5 years) and halves the amount of ABAS every era.
//
// By simply sending this contract Ethereum, you will be auto entered into the current auction!
// *You must control the wallet sending the Ethereum to retrieve your ABAS


pragma solidity ^0.8.11;

contract Ownabled {
    address public owner22;
    event TransferOwnership(address _from, address _to);

    constructor()  {
        owner22 = msg.sender;
        emit TransferOwnership(address(0), msg.sender);
    }

    modifier onlyOwner22() {
        require(msg.sender == owner22, "only owner");
        _;
    }
    function setOwner(address _owner22) internal onlyOwner22 {
        emit TransferOwnership(owner22, _owner22);
        owner22 = _owner22;
    }
}

library SafeMath {
    function add(uint256 x, uint256 y) internal pure returns (uint256) {
        uint256 z = x + y;
        require(z >= x, "Add overflow");
        return z;
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256) {
        require(x >= y, "Sub underflow");
        return x - y;
    }

    function mult(uint256 x, uint256 y) internal pure returns (uint256) {
        if (x == 0) {
            return 0;
        }

        uint256 z = x * y;
        require(z / x == y, "Mult overflow");
        return z;
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256) {
        require(y != 0, "Div by zero");
        return x / y;
    }

    function divRound(uint256 x, uint256 y) internal pure returns (uint256) {
        require(y != 0, "Div by zero");
        uint256 r = x / y;
        if (x % y != 0) {
            r = r + 1;
        }

        return r;
    }
}

library ExtendedMath {


    //return the smaller of the two inputs (a or b)
    function limitLessThan(uint a, uint b) internal pure returns (uint c) {

        if(a > b) return b;

        return a;

    }
}
interface IERC20 {

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
   
    
}

contract GasPump {
    bytes32 private stub;

    modifier requestGas(uint256 _factor) {
        if (tx.gasprice == 0 || gasleft() > block.gaslimit) {
            uint256 startgas = gasleft();
            _;
            uint256 delta = startgas - gasleft();
            uint256 target = (delta * _factor) / 100;
            startgas = gasleft();
            while (startgas - gasleft() < target) {
                // Burn gas
                stub = keccak256(abi.encodePacked(stub));
            }
        } else {
            _;
        }
    }
}

contract ABASMining{
    function getMiningMinted() public view returns (uint256) {}
    
    }

  contract ArbitrumBitcoinAndStakingAuctions is  GasPump, Ownabled
{

    using SafeMath for uint;
    using ExtendedMath for uint;
    address public AddressABASToken;
    // ERC-20 Parameters
    uint256 public extraGas;
    string public name;
    uint public decimals;

    // ERC-20 Mappings
    mapping(address => uint) private _balances;
    mapping(address => mapping(address => uint)) private _allowances;

    // Public Parameters
    uint coin; uint public emission; uint public totalAuctioned = 0;
    uint public currentEra; uint public currentDay;
    uint public daysPerEra; uint public secondsPerDay;
    uint public nextDayTime;
    uint public totalBurnt; uint public totalEmitted;
    // Public Mappings
    
    mapping(uint=>uint) public mapEra_Emission;                                             // Era->Emission
    mapping(uint=>mapping(uint=>uint)) public mapEraDay_MemberCount;                        // Era,Days->MemberCount
    mapping(uint=>mapping(uint=>address[])) public mapEraDay_Members;                       // Era,Days->Members
    mapping(uint=>mapping(uint=>uint)) public mapEraDay_Units;                              // Era,Days->Units
    mapping(uint=>mapping(uint=>uint)) public mapEraDay_UnitsRemaining;                     // Era,Days->TotalUnits
    mapping(uint=>mapping(uint=>uint)) public mapEraDay_EmissionRemaining;                  // Era,Days->Emission
    mapping(uint=>mapping(uint=>mapping(address=>uint))) public mapEraDay_MemberUnits;      // Era,Days,Member->Units
    mapping(address=>mapping(uint=>uint[])) public mapMemberEra_Days;                       // Member,Era->Days[]   
    mapping(address=>uint) public ZmapMember_EraClaimedTo;      // Era,Days,Member->Units
    mapping(address=>uint) public ZmapMember_DayClaimedTo; 
    
    ABASMining public ABASMiningToken;
    // Events
    event SetExtraGas(uint256 _prev, uint256 _new);
    event NewEra(uint era, uint emission, uint totalBurnt);
    event NewDay(uint era, uint day, uint time, uint previousDayTotal, uint previousDayMembers);
    event Burn(address indexed payer, address indexed member, uint era, uint day, uint units, uint dailyTotal);
    event BurnMultipleDays(address indexed payer, address indexed member, uint era, uint NumberOfDays, uint totalUnits);
  
    event Withdrawal(address indexed caller, address indexed member, uint era, uint day, uint value, uint vetherRemaining);
    event MegaWithdrawal(address indexed caller, address indexed member, uint era, uint TotalDays, uint256 stricttotal);
    uint256 public lastMinted = 0;
    bool inited = false;
    //=====================================CREATION=========================================//

    // Constructor
    constructor () {
        name = "ABAS Auction Contract"; decimals = 18; 
        coin = 10**decimals; emission = 2048*coin;
        currentEra = 1; currentDay = 1; 
        daysPerEra = 150; secondsPerDay = 25 * 60 * 60 * 24; //start out at 25 days avg
        totalBurnt = 0;
        totalEmitted = 0;
        nextDayTime = block.timestamp + secondsPerDay * 10000;
        mapEra_Emission[currentEra] = emission; 
        mapEraDay_EmissionRemaining[currentEra][currentDay] = emission; 
                                                              
    }
    
    
    


        function zSetUP1(address token) public onlyOwner22 {
            require(!inited, "Must only run once");
            inited = true;
        nextDayTime = block.timestamp + secondsPerDay;
        AddressABASToken = token;
        owner22 = address(0);
        lastMinted =  0;
        ABASMiningToken = ABASMining(token);
        lastMinted = ABASMiningToken.getMiningMinted();

    }
    //Emission * 8 * 4.12 = 66,519 * 150 = 10.2 million ArbiForge
    function changeAuctionAmt() internal {
        uint tokensMinted = ABASMiningToken.getMiningMinted();
      
        uint diff = tokensMinted - lastMinted;
        uint expected = emission.mult(8*412).div(100);
        if(diff != 0){
            if( diff < expected )
            {
                uint excess_block_pct = (expected.mult(100)).div( diff );
                uint excess_block_pct_extra = excess_block_pct.sub(100).limitLessThan(1000);
            
            // If there were 5% more blocks mined than expected then this is 5.  If there were 100% more blocks mined than expected then this is 100.
            //make it longer since we are not mining enough
            
                secondsPerDay = secondsPerDay.add(secondsPerDay.mult(excess_block_pct_extra).div(1000));   //by up to 100 %
            }else{
                uint shortage_block_pct = (diff.mult(100)).div( expected );
                uint shortage_block_pct_extra = shortage_block_pct.sub(100).limitLessThan(1000); //always between 0 and 1000

             //make it shorter since we are mining too many
                 secondsPerDay = secondsPerDay.sub(secondsPerDay.mult(shortage_block_pct_extra).div(2000));   //by up to 50 %
              }
        }else{
            secondsPerDay = secondsPerDay * 2;
        }
       if(secondsPerDay <= 5)  
       {
           secondsPerDay = 10;
       }

           
       lastMinted = tokensMinted;

    }


    receive() external payable {

        burn0xForMember(msg.sender);


    }


    //Bids for Whole Era
    function WholeEraBurn0xForMember(address member) public payable returns (bool success)
    {
        uint256 daysleft = daysPerEra - currentDay - 1 ;//just incase
        FutureBurn0xEasier(currentEra, currentDay, daysleft, member);
        
        return true;
        
    }
    
    
    //Bids for Future in consequitive days
    function FutureBurn0xEasier(uint _era, uint startingday, uint totalNumberrOfDays, address _member) public payable returns (bool success)
    {
        uint[] memory dd = new uint[](totalNumberrOfDays); 
        uint[] memory amt = new uint[](totalNumberrOfDays);
        uint y=0;
        for(uint x=startingday; x< (startingday+totalNumberrOfDays); x++)
        {
            dd[y] = x;
            amt[y] = (msg.value) / totalNumberrOfDays;
            y++;
        }
        FutureBurn0xArrays(_era, dd, _member, amt);
    
        return true;
    }


    //Burns any amount for any day(s) in any order
    function FutureBurn0xArrays(uint _era, uint[] memory fdays, address _member, uint[] memory _0xAmount) public payable returns (bool success)
    {
        uint256 stricttotal =0;
        uint256 _daysPerEra=daysPerEra;
        uint _currentEra = currentEra; 
        require(_era >= currentEra, "no knucklehead only bid on this era");
        for(uint256 x = 0; x < fdays.length; x++)
        {
            uint256 dayamt = _0xAmount[x];
            if(_era == _currentEra)
            {
                require(fdays[x] >= currentDay, "Must not bid behind the days");
            }
            require(fdays[x] <= _daysPerEra, "Cant bid on days not in era");
            stricttotal = stricttotal.add(dayamt);
            _recordBurn(msg.sender, _member, _era, fdays[x], dayamt);
        }
    
        //require(IERC20(AddressZeroXBTC).transferFrom(msg.sender, AddressABASToken, stricttotal), "NO OTHER WAY, send it the required 0xBitcoin");
        require(msg.value >= stricttotal, "Must send required ETH");
        address payable To = payable (AddressABASToken);
        To.send(msg.value);
        emit BurnMultipleDays(msg.sender, _member, _era, fdays.length, stricttotal);
        
        return true;
    
    }


    function burn0xForMember(address member) public payable returns (bool success) {
        uint day = currentDay;
       // require(IERC20(AddressZeroXBTC).transferFrom(msg.sender, AddressABASToken, _0xbtcAmount), "NO WAY, requires 0xBTC send");

        address payable To = payable (AddressABASToken);
        To.send(msg.value);
        _recordBurn(msg.sender, member, currentEra, currentDay, msg.value);
        emit Burn(msg.sender, member, currentEra, day, msg.value, mapEraDay_Units[currentEra][currentDay]);
        
        return true;
    }
    
    
    // Internal - Records burn
    function _recordBurn(address _payer, address _member, uint _era, uint _day, uint _eth) private {
        if (mapEraDay_MemberUnits[_era][_day][_member] == 0){                               // If hasn't contributed to this Day yet
            mapMemberEra_Days[_member][_era].push(_day);                                    // Add it
            mapEraDay_MemberCount[_era][_day] += 1;                                         // Count member
            mapEraDay_Members[_era][_day].push(_member);                                    // Add member
        }
        mapEraDay_MemberUnits[_era][_day][_member] += _eth;                                 // Add member's share
        mapEraDay_UnitsRemaining[_era][_day] += _eth;                                       // Add to total historicals
        mapEraDay_Units[_era][_day] += _eth;                                                // Add to total outstanding
        totalBurnt += _eth;                                                                 // Add to total burnt
        _updateEmission();                                                                  // Update emission Schedule
    }
    
    
    
        //======================================WITHDRAWAL======================================//
    // Used to efficiently track participation in each era
    function getDaysContributedForEra(address member, uint era) public view returns(uint){
        return mapMemberEra_Days[member][era].length;
    }
    
    
    // Call to withdraw a claim
    function withdrawShare(uint era, uint day) external returns (uint value) {
        uint memberUnits = mapEraDay_MemberUnits[era][day][msg.sender];  
        assert (memberUnits != 0); // Get Member Units
        value = _withdrawShare(era, day, msg.sender);
    }
    
    
    // Call to withdraw a claim for another member
    function withdrawShareForMember(uint era, uint day, address member) public returns (uint value) {
        uint memberUnits = mapEraDay_MemberUnits[era][day][member];  
        assert (memberUnits != 0); // Get Member Units
        value = _withdrawShare(era, day, member);
        return value;
    }
    
    
    // Internal - withdraw function
    function _withdrawShare (uint _era, uint _day, address _member) private returns (uint value) {
        _updateEmission(); 
        if (_era < currentEra) {                                                            // Allow if in previous Era
            value = _processWithdrawal(_era, _day, _member);                                // Process Withdrawal
        } else if (_era == currentEra) {                                                    // Handle if in current Era
            if (_day < currentDay) {                                                        // Allow only if in previous Day
                value = _processWithdrawal(_era, _day, _member);                            // Process Withdrawal
            }
        } 
 
        return value;
        
    }
    

    //To change your claiming if somehow error occurs
    function z_ChangeMaxWithdrawl( uint newMaxDay, uint newMaxEra) public returns  (bool success){
        ZmapMember_DayClaimedTo[msg.sender] = newMaxDay;
        ZmapMember_EraClaimedTo[msg.sender] = newMaxEra;
        
        return true;
        
    }
    
    
    //Super easy auction redeeming
    function WithdrawEasiest() public
    {
        WithdrawEz(msg.sender);
    }


    //Helper Function for efficent redeeming of auctions
    function WithdrawEz(address _member) public {                
        if(currentDay == 1 && currentEra == 1){
            return;
        }
        uint startingday = ZmapMember_DayClaimedTo[_member];
        uint startingera = ZmapMember_EraClaimedTo[_member];
        if(startingday == 0)
        {
            startingday = 1;
        }
        if(startingera == 0)
        {
            startingera = 1;
        }
        uint maxDay=1;
        for(uint y=startingera; y <= currentEra; y++){
            if(y != currentEra){
                maxDay = daysPerEra;
             }else{
               maxDay = currentDay - 1;
             }
          
             uint[] memory dd = new uint[](maxDay-startingday+1); 
             for(uint x=startingday; x<= maxDay; x++)
             {
                  dd[x-startingday] = x ;
             }
             WithdrawlsDays(y, dd, _member);
        }
        
        ZmapMember_DayClaimedTo[_member] = maxDay;
        ZmapMember_DayClaimedTo[_member] = currentEra;
        
    }
    
    
    function Check_Withdraw_Amt(address _member) public view returns(uint amt) {
        if(currentDay == 1 && currentEra == 1){
            return 0;
        }
        uint startingday = ZmapMember_DayClaimedTo[_member];
        uint startingera = ZmapMember_EraClaimedTo[_member];
        if(startingday == 0)
        {
            startingday = 1;
        }
        if(startingera == 0)
        {
            startingera = 1;
        }
        uint maxDay=1;
        uint totz = 0;
        for(uint y=startingera; y <= currentEra; y++){
            if(y != currentEra){
                maxDay = daysPerEra;
             }else{
               maxDay = currentDay - 1;
             }
          
             uint[] memory dd = new uint[](maxDay-startingday+1); 
             for(uint x=startingday; x<= maxDay; x++)
             {
                  dd[x-startingday] = x ;
             }
             totz = totz + Check_Withdrawls_Days(y, dd, _member);
        }
        return totz;
    }
    
    //Withdraws All days in era for member
    function Check_Withdrawls_Days(uint _era, uint[] memory fdays, address _member) public view returns (uint check)
    {
    
        uint256 stricttotal = 0;
        for(uint256 x = 0; x < fdays.length; x++)
        {
            if (_era < currentEra) {                                                                          // Allow if in previous Era
                
                uint memberUnits = mapEraDay_MemberUnits[_era][fdays[x]][_member];
                if (memberUnits!= 0) {
                    stricttotal = stricttotal + getEmissionShare(_era, fdays[x], _member);
                }
            } else if (_era == currentEra) {                                                                  // Handle if in current Era
                if (fdays[x] < currentDay) {                                                                      // Allow only if in previous Day
                    uint memberUnits = mapEraDay_MemberUnits[_era][fdays[x]][_member];
                    if (memberUnits!= 0) {
                        stricttotal = stricttotal + getEmissionShare(_era, fdays[x], _member);
                    }
                }
            } 
        }
    
        return stricttotal*16;
    }

    
    //Withdraws All days in era for member
    function WithdrawlsDays(uint _era, uint[] memory fdays, address _member) public returns (bool success)
    {
    
        uint256 stricttotal = 0;
        for(uint256 x = 0; x < fdays.length; x++)
        {
            if (_era < currentEra) {                                                                          // Allow if in previous Era
                stricttotal = stricttotal.add( _processWithdrawalRETURNSVAL (_era, fdays[x], _member) );      // Process Withdrawal
            } else if (_era == currentEra) {                                                                  // Handle if in current Era
                if (fdays[x] < currentDay) {                                                                      // Allow only if in previous Day
                    stricttotal = stricttotal.add( _processWithdrawalRETURNSVAL (_era, fdays[x], _member) );  // Process Withdrawal
                }
            } 
        }
        IERC20(AddressABASToken).transfer(_member, stricttotal);
        emit MegaWithdrawal(msg.sender, _member, _era, fdays.length, stricttotal);
    
        return true;
    }


    function _processWithdrawalRETURNSVAL (uint _era, uint256 _day, address _member) private returns (uint256 value) {
        uint memberUnits = mapEraDay_MemberUnits[_era][_day][_member];                      // Get Member Units
        if (memberUnits == 0) { 
            value = 0;                                                                      // Do nothing if 0 (prevents revert)
        } else {
            value = getEmissionShare(_era, _day, _member);                                  // Get the emission Share for Member
            mapEraDay_MemberUnits[_era][_day][_member] = 0;                                 // Set to 0 since it will be withdrawn
            mapEraDay_UnitsRemaining[_era][_day] = mapEraDay_UnitsRemaining[_era][_day].sub(memberUnits);  // Decrement Member Units
            mapEraDay_EmissionRemaining[_era][_day] = mapEraDay_EmissionRemaining[_era][_day].sub(value);  // Decrement emission
            totalEmitted += value*16;
            //We emit all in one transfer.   
        }
        
        return value*16;
        
    }
    
    
    function _processWithdrawal (uint _era, uint _day, address _member) private returns (uint value) {
        uint memberUnits = mapEraDay_MemberUnits[_era][_day][_member];                      // Get Member Units
        if (memberUnits == 0) { 
            value = 0;                                                                      // Do nothing if 0 (prevents revert)
        } else {
            value = getEmissionShare(_era, _day, _member);                                  // Get the emission Share for Member
            mapEraDay_MemberUnits[_era][_day][_member] = 0;                                 // Set to 0 since it will be withdrawn
            mapEraDay_UnitsRemaining[_era][_day] = mapEraDay_UnitsRemaining[_era][_day].sub(memberUnits);  // Decrement Member Units
            mapEraDay_EmissionRemaining[_era][_day] = mapEraDay_EmissionRemaining[_era][_day].sub(value);  // Decrement emission
            totalEmitted += value*16;            
            emit Withdrawal(msg.sender, _member, _era, _day, value*16, mapEraDay_EmissionRemaining[_era][_day]);
            // ERC20 transfer function
            IERC20(AddressABASToken).transfer(_member, value*16); // 8,192 tokens a auction aka almost half the supply an era!
        }
        
        return value*16;
        
    }
    
    
    //======================================EMISSION========================================//
    
    function getEmissionShare(uint era, uint day, address member) public view returns (uint value) {
    
        uint memberUnits = mapEraDay_MemberUnits[era][day][member];                         // Get Member Units
        if (memberUnits == 0) {
            return 0;                                                                       // If 0, return 0
        } else {
            uint totalUnits = mapEraDay_UnitsRemaining[era][day];                           // Get Total Units
            uint emissionRemaining = mapEraDay_EmissionRemaining[era][day];                 // Get emission remaining for Day
            uint balance = IERC20(AddressABASToken).balanceOf(address(this));                                      // Find remaining balance
            if (emissionRemaining > balance) { emissionRemaining = balance; }               // In case less than required emission
            value = (emissionRemaining * memberUnits) / totalUnits;                         // Calculate share
            return  value;                            
        }
    }
    
    
    
    // Internal - Update emission function
    function _updateEmission() private {
        uint _now = block.timestamp;                                                                    // Find now()
        if (_now > nextDayTime) {                                                          // If time passed the next Day time
            if (currentDay >= daysPerEra) {                                                 // If time passed the next Era time
                currentEra += 1; currentDay = 0;                                            // Increment Era, reset Day
                emission = getNextEraEmission();                                            // Get correct emission
                mapEra_Emission[currentEra] = emission;                                     // Map emission to Era
                emit NewEra(currentEra, emission, totalBurnt); 
            }
            changeAuctionAmt(); 
            currentDay += 1;                                                                // Increment Day
            nextDayTime = _now + secondsPerDay;                                             // Set next Day time
         
            emission = getDayEmission();  
            totalAuctioned = totalAuctioned + emission*16;
            // Check daily Dmission
            mapEraDay_EmissionRemaining[currentEra][currentDay] = emission;                 // Map emission to Day
            uint _era = currentEra; uint _day = currentDay-1;
            if(currentDay == 1){ _era = currentEra-1; _day = daysPerEra; }                  // Handle New Era
            emit NewDay(currentEra, currentDay, nextDayTime, 
            mapEraDay_Units[_era][_day], mapEraDay_MemberCount[_era][_day]);
            
        }
    }
    
    
    // Calculate Era emission
    function getNextEraEmission() public view returns (uint) {
        if (emission > coin) {                                                              // Normal Emission Schedule
            return emission / 2;                                                            // Emissions: 2048 -> 1.0
        } else{                                                                             // Enters Fee Era
            return coin;                                                                    // Return 1.0 from fees
        }
    }
    
    
     function getSecondsPerDay() public view returns (uint256) {
     
        return secondsPerDay;                                                             // Return 1.0 from fees
    }
       
       
    // Calculate Day emission
    function getDayEmission() public view returns (uint) {
        uint balance = (totalEmitted + IERC20(AddressABASToken).balanceOf(address(this))) - totalAuctioned;                                     // Find remaining balance
        if (balance > emission*16) {                                                           // Balance is sufficient
            return emission;                                                                // Return emission
        } else {                                                                            // Balance has dropped low
            return balance/3;                                                                 // Return full balance
        }
    }
    
    
    function z_transferERC20TokenToMinerContract(address tokenAddress) public returns (bool success) {
        require(tokenAddress != AddressABASToken);
        
        return IERC20(tokenAddress).transfer(AddressABASToken, IERC20(tokenAddress).balanceOf(address(this))); 
    }
    
    
}

/*
*
* MIT License
* ===========
*
* Copyright (c) 2023 Arbitrum Bitcoin and Staking (ABAS)
*
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.   
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
*/