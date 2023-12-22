// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";

import { IDLPRush } from "./IRadpieIDODataReader.sol";
import { IVlmgp } from "./IRadpieIDODataReader.sol";
import { IBurnEventManager } from "./IRadpieIDODataReader.sol";
import { IRadpieReader } from "./IRadpieIDODataReader.sol";
import { IPendleRushV4 } from "./IRadpieIDODataReader.sol";
import { IDlpHelper } from "./IRadpieIDODataReader.sol";

import { ReaderDatatype } from "./ReaderDatatype.sol";

/// @title RadpieIdoDataReader
/// @author Magpie Team

contract RadpieIdoDataReader is Initializable, OwnableUpgradeable, ReaderDatatype {

       /* ============ State Variables ============ */

       IDLPRush public dlpRush;
       IVlmgp public vlmgp;
       IBurnEventManager public burnEventManager;
       IRadpieReader public radpieReader;
       IPendleRushV4 public pendleRushV4;

       uint256 public totalWomConvereted;
       mapping(address => uint256) public userConvertedWom;

       address public radpieAdmin = 0x0CdB34e6a4D635142BB92fe403D38F636BbB77b8;

       /* ============ Structs ============ */

       struct RadpieIdoData {
              uint256 totalMdlpConverterd;
              uint256 userConvertedMdlp;
              uint256 totalLockedMgp;
              uint256 userLockedMgp;
              uint256 totelBurnedMgpInEventByUser;
              uint256  totelBurnedMgpInGivenEvent;
              uint256 totalRadpieTvl;
              uint256 userTotalTvlInRadpieExcludeMDlp;
              userTvlInfo[] usertvlinfo; 
              uint256 totelmPendleConverted;
              uint256 totelmPendleConvertedByUser;
              uint256 totalWomConvereted;
              uint256 userConvertedWom;
       }

       struct userTvlInfo {
              address poolAddress;
              uint256 usersTvl;
       }

       IDlpHelper public dlpHelper;

    /* ============ Errors ============ */

       error IsZeroAddress();
       error IsZeroAmount();

    /* ============ Constructor ============ */

       function __RadpieIdoDataReader_init(
              address _dlpRush, 
              address _vlMgp, 
              address _burnEventManager, 
              address _radpieReader,
              address _pendleRushV4,
              address _dlpHelper
       ) 
       public initializer 
       {
              __Ownable_init();
              dlpRush = IDLPRush(_dlpRush);
              vlmgp = IVlmgp(_vlMgp);
              burnEventManager = IBurnEventManager(_burnEventManager);
              radpieReader = IRadpieReader(_radpieReader);
              pendleRushV4 = IPendleRushV4(_pendleRushV4);
              dlpHelper = IDlpHelper(_dlpHelper);
       }

    /* ============ External Getters ============ */

       function getMDlpHoldersData( address _user ) external view returns( uint256 totalMdlpConverterd, uint256 userConvertedMdlp)
       {   
              if(address(dlpRush) != address(0)) 
              {
                     totalMdlpConverterd = dlpRush.totalConverted() * dlpHelper.getPrice() ; 
                     userConvertedMdlp = dlpRush.userInfos(_user).converted * dlpHelper.getPrice();
              }
       }

       function getvlLMgpHoldersData( address _user ) external view returns( uint256 totalLockedMgp, uint256 userLockedMgp )
       {   
              if(address(vlmgp) != address(0)) 
              {
                     totalLockedMgp = vlmgp.totalLocked(); 
                     userLockedMgp = vlmgp.getUserTotalLocked(_user);
              }
       }

       function getMgpBurnersData( uint256 _eventId, address _user ) external view returns( uint256 totelBurnedMgpInEventByUser, uint256 totelBurnedMgpInGivenEvent)
       {   
              if(address(burnEventManager) != address(0)) 
              {
                     totelBurnedMgpInEventByUser = burnEventManager.userMgpBurnAmountForEvent(_user, _eventId);
                     (,, totelBurnedMgpInGivenEvent, ) = burnEventManager.eventInfos(_eventId);
              }
       }

       function getRadpieTvlProvidersData( address _user ) external view returns( uint256 totalRadpieTvl, userTvlInfo[] memory, uint256 userTotalTvlInRadpieExcludeMDLp )
       {
              uint256 _userTotalTvlInRadpieExcludeMDlp;
              userTvlInfo[] memory usertvlinfo;

              if(address(radpieReader) != address(0)) 
              {
                     RadpieInfo memory radpieinfo = radpieReader.getRadpieInfo(radpieAdmin);

                     for(uint256 i = 1; i < radpieinfo.pools.length; i++) // at 0 index mPendle that excluded.
                     {
                            totalRadpieTvl += radpieinfo.pools[i].tvl;
                     }   

                     RadpiePool[] memory pools = new RadpiePool[](radpieinfo.pools.length);
                     usertvlinfo = new userTvlInfo[](radpieinfo.pools.length - 1);   

                     for (uint256 i = 1; i < radpieinfo.pools.length; ++i) { // at 0 index mPendle that excluded.
                            pools[i] =  radpieReader.getRadpiePoolInfo(i, _user, radpieinfo);
                            usertvlinfo[i - 1].poolAddress = pools[i].asset;
                            usertvlinfo[i - 1].usersTvl = pools[i].accountInfo.tvl;
                            _userTotalTvlInRadpieExcludeMDlp += pools[i].accountInfo.tvl;
                     }  
              }

              return (totalRadpieTvl, usertvlinfo, _userTotalTvlInRadpieExcludeMDlp);
       }

       function getmPendleConverterData( address _user ) external view returns( uint256 totelmPendleConverted, uint256 totelmPendleConvertedByUser)
       {   
              if(address(pendleRushV4) != address(0)) 
              {
                     totelmPendleConverted =  pendleRushV4.totalAccumulated();     
                     ( totelmPendleConvertedByUser, ) = pendleRushV4.userInfos(_user); 
              }
       }

       function getWomConverterDataInWomUp(address _user) external view returns(uint256 _totalWomConvereted, uint256 _userConvertedWom)
       {
             
              _userConvertedWom = userConvertedWom[_user];
              _totalWomConvereted = totalWomConvereted;
       } 

       function getRadpieIdoData( uint256 _mgpBurnEventId, address _user ) external view returns ( RadpieIdoData memory )
       {
              RadpieIdoData memory radpieidodata;

              if(address(dlpRush) != address(0)) 
              {
                     radpieidodata.totalMdlpConverterd = dlpRush.totalConverted(); 
                     radpieidodata.userConvertedMdlp = dlpRush.userInfos(_user).converted;
              } 
              if(address(vlmgp) != address(0)) 
              {
                     radpieidodata.totalLockedMgp = vlmgp.totalLocked(); 
                     radpieidodata.userLockedMgp = vlmgp.getUserTotalLocked(_user);
              }
              if(address(burnEventManager) != address(0)) 
              {
                     radpieidodata.totelBurnedMgpInEventByUser = burnEventManager.userMgpBurnAmountForEvent(_user, _mgpBurnEventId);
                     (,, radpieidodata.totelBurnedMgpInGivenEvent, ) = burnEventManager.eventInfos(_mgpBurnEventId);
              }
              
              if(address(radpieReader) != address(0)) 
              {
                     // uint256 totalRadpieTvl;
                     RadpieInfo memory radpieinfo = radpieReader.getRadpieInfo(radpieAdmin);       
                     for(uint256 i = 1; i < radpieinfo.pools.length; i++) // at 0 index mPendle that excluded.
                     {
                            radpieidodata.totalRadpieTvl += radpieinfo.pools[i].tvl;
                     }   

                     RadpiePool[] memory pools = new RadpiePool[](radpieinfo.pools.length);
                     userTvlInfo[] memory _usertvlinfo = new userTvlInfo[](radpieinfo.pools.length - 1);   

                     for (uint256 i = 1; i < radpieinfo.pools.length; ++i) { // at 0 index mPendle that excluded.
                            pools[i] =  radpieReader.getRadpiePoolInfo(i, _user, radpieinfo);
                            _usertvlinfo[i - 1].poolAddress = pools[i].asset;
                            _usertvlinfo[i - 1].usersTvl = pools[i].accountInfo.tvl;
                            radpieidodata.userTotalTvlInRadpieExcludeMDlp += pools[i].accountInfo.tvl;
                     }  
                     radpieidodata.usertvlinfo = _usertvlinfo;
              }
              if(address(pendleRushV4) != address(0)) 
              {
                     radpieidodata.totelmPendleConverted =  pendleRushV4.totalAccumulated();     
                     (radpieidodata.totelmPendleConvertedByUser, ) = pendleRushV4.userInfos(_user); 
              }

              radpieidodata.totalWomConvereted = totalWomConvereted;
              radpieidodata.userConvertedWom = userConvertedWom[_user];

              return radpieidodata;
       }

    /* ============ Admin functions ============ */

       function config(
              address _dlpRush, 
              address _vlMgp, 
              address _burnEventManager, 
              address _radpieReader,
              address _pendleRushV4,
              address _dlpHelper,
              address _radpieAdmin
       ) external onlyOwner {
              dlpRush = IDLPRush(_dlpRush);
              vlmgp = IVlmgp(_vlMgp);
              burnEventManager = IBurnEventManager(_burnEventManager);
              radpieReader = IRadpieReader(_radpieReader);
              pendleRushV4 = IPendleRushV4(_pendleRushV4);
              dlpHelper = IDlpHelper(_dlpHelper);
              radpieAdmin = _radpieAdmin;
       }

       function setUsersWomConvertedDataInWomUp(address[] memory _users, uint256[] memory _amounts) external onlyOwner
       {
              for( uint256 i = 0; i < _users.length; i++)
              {
                     totalWomConvereted += _amounts[i];
                     userConvertedWom[_users[i]] = _amounts[i];
              }
       }

       function setDlpHelper(address _dlpHelper) external onlyOwner
       {
              dlpHelper = IDlpHelper(_dlpHelper);
       }
}

