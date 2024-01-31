// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//3DABFL data.

import "./Strings.sol";


abstract contract data_3DABFL{
    string[] private sports = [
        "\'0 -0.5 0 -0.5 0 0.5 0 1 0 -0.5 0 1.57 0 -0.5 0 -0.5\'",
        "\'0 -0.5 0 0.5 0 -0.5 0 1 0 0.5 0 1.57 0 -0.5 0 0.5\'"
    ];
    string[] private size = [
        "\'0.2 2.0 0.2\'",
        "\'0.4 0.3 0.5\'",
        "\'0.03 0.6 0.03\'",
        "\'0.03 0.6 0.03\'",
        "\'0.3 0.03 0.03\'",
        "\'0.3 0.03 0.03\'",
        "\'3 1 0.01\'",
        "\'3.2 0.3 0.01\'",
        "\'3.2 0.3 0.01\'",
        "\'1.6 0.2 0.01\'",
        "\'1.8 1.0 0.01\'",
        "\'1.5 0.2 0.01\'",
        "\'0.2 1.2 0.01\'",
        "\'0.2 0.6 0.01\'",
        "\'0.75 0.75 0.02\'",
        "\'0.3 0.3 0.02\'",
        "\'0.3 0.3 0.02\'",
        "\'0.3 0.3 0.02\'",
        "\'0.2 0.8 0.02\'",
        "\'0.5 0.5 0.02\'",
        "\'0.5 0.5 0.02\'"
    ];
    string[] private XYZ = [
        "\'0 0.5 0\'",
        "\'0 1.1 -0.1\'",
        "\'0.1 1.8 0\'",
        "\'-0.1 1.8 0\'",
        "\'-0.25 2.1 0\'",
        "\'0.25 2.1 0\'",
        "\'1.7 0.7 0\'",
        "\'2.2 1.65 0\'",
        "\'1.9 1.35 0\'",
        "\'1 0.1 0\'",
        "\'1.1 -0.5 0\'",
        "\'1.1 -1.1 0\'",
        "\'1.4 -1.8 0\'",
        "\'1.0 -1.5 0\'",
        "\'0.8 0.7 0\'",
        "\'1.8 0.7 0\'",
        "\'1.5 1 0\'",
        "\'2.3 0.5 0\'",
        "\'2.9 0.7 0\'",
        "\'0.7 -0.4 0\'",
        "\'1.5 -0.6 0\'",
        "\'-1.7 0.7 0\'",
        "\'-2.2 1.65 0\'",
        "\'-1.9 1.35 0\'",
        "\'-1 0.1 0\'",
        "\'-1.1 -0.5 0\'",
        "\'-1.1 -1.1 0\'",
        "\'-1.4 -1.8 0\'",
        "\'-1.0 -1.5 0\'",
        "\'-0.8 0.7 0\'",
        "\'-1.8 0.7 0\'",
        "\'-1.5 1 0\'",
        "\'-2.3 0.5 0\'",
        "\'-2.9 0.7 0\'",
        "\'-0.7 -0.4 0\'",
        "\'-1.5 -0.6 0\'"
    ];

    using Strings for uint256;
    string internal _Sugar;

    function R(string memory s) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(s)));
    }

    function getDNA(uint256 tokenId) public view returns (string memory) {
        return
            string(
                
                    R(string(abi.encodePacked(_Sugar, tokenId.toString()))).toHexString()

            );
    }

    function getAttr1(uint256 tokenId) public view returns (bool ) {
        uint256 seed = R(string(abi.encodePacked("U", getDNA(tokenId))));
        return bool(seed % 100 < 45);
    }

    function getAttr2(uint256 tokenId) public view returns (bool ) {
        uint256 seed = R(string(abi.encodePacked("M", getDNA(tokenId))));
        return bool(seed % 10 < 4);
    }

    function getAttr3(uint256 tokenId) public view returns (bool) {
        uint256 seed = R(string(abi.encodePacked("D", getDNA(tokenId))));
        return bool(seed % 10 < 3);
    }
    function getColor(uint256 tokenId , uint256 _x) public view returns (string memory) {
        uint256 C1 = R(string(abi.encodePacked("R", _x.toString() , getDNA(tokenId)))) % 100;
        uint256 C2 = R(string(abi.encodePacked("G",_x.toString() , getDNA(tokenId)))) % 100;
        uint256 C3 = R(string(abi.encodePacked("B",_x.toString() , getDNA(tokenId)))) % 100;
        return string(abi.encodePacked("\'0.",C1.toString()," ","0.",C2.toString()," ","0.",C3.toString(),"\'"));
    }
    function getHTML(uint256 tokenId,string memory _X3D)
        internal 
        view
        returns (string memory)
    {
        require(tokenId > 0 && tokenId < 7001, "Token ID invalid");
        string[5] memory Ls1;
        string[7] memory Ls2;
        string[6] memory Ls3;
        uint8 y = 6;
        string memory M_1;
        string memory M_2;
        string memory M_3;
        string memory L_1;
        string memory L_2;
        string memory L_3;
        Ls1[0] = '<html><head><meta http-equiv=\'X-UA-Compatible\' content=\'IE=edge\' /><script type=\'text/javascript\' src=';
        Ls1[1] = _X3D;
        Ls1[2] = '> </script></head><body><x3d width=\'100%\' height=\'100%\'><scene><background skyColor=';
        Ls1[3] = getColor(tokenId , 1024);
        Ls1[4] = '></background> ';
        //Ls1[5] = "Copy the following content into the HTML file and open it for viewing";
        Ls3[5] = '</scene></x3d></body></html> ';

        Ls2[0] = '<transform translation=';
        Ls2[2] = ' visible=\'true\'><shape><appearance><material diffuseColor=';
        Ls2[4] = '></material></appearance><Box size=';
        Ls2[6] = '></Box></shape></transform>';

        Ls3[0] = '<transform DEF=';
        Ls3[1] = ' >  ';
        Ls3[2] = ' </transform><timeSensor DEF=\'Clock\' cycleInterval=\'2.0\' loop=\'true\'></timeSensor><OrientationInterpolator DEF=\'ColumnPath\' key=\'0.0 0.20 0.6 1.0\' keyValue=';
        Ls3[3] = '></OrientationInterpolator><Route fromNode=\'Clock\' fromField=\'fraction_changed\' toNode=\'ColumnPath\' toField=\'set_fraction\'></Route><Route fromNode=\'ColumnPath\' fromField=\'value_changed\' toNode=';
        Ls3[4] = ' toField=\'set_rotation\'></Route>';
        for (uint8 i = 0; i < 36; i++) {
            Ls2[1]  = XYZ[i];
            Ls2[3] = getColor(tokenId , i);
            if (i<6){
                Ls2[5] = size[i];
                M_1 = string(abi.encodePacked(M_1,Ls2[0],Ls2[1],Ls2[2]));
                M_1 = string(abi.encodePacked(M_1,Ls2[3],Ls2[4],Ls2[5],Ls2[6]));
            }else if(i<21){
                Ls2[5] = size[i];
                if(i==7){
                    if(getAttr1(tokenId)){
                        M_2 = string(abi.encodePacked(M_2,Ls2[0],Ls2[1],Ls2[2],Ls2[3]));
                        M_2 = string(abi.encodePacked(M_2,Ls2[4],Ls2[5],Ls2[6]));
                    }else{M_2 = string(abi.encodePacked(M_2,' '));}
                }else if(i==12){
                    if(getAttr3(tokenId)){
                        M_2 = string(abi.encodePacked(M_2,Ls2[0],Ls2[1],Ls2[2],Ls2[3]));
                        M_2 = string(abi.encodePacked(M_2,Ls2[4],Ls2[5],Ls2[6]));
                    }else{M_2 = string(abi.encodePacked(M_2,' '));}
                }else if(i==13){
                    if(getAttr2(tokenId)){
                        M_2 = string(abi.encodePacked(M_2,Ls2[0],Ls2[1],Ls2[2],Ls2[3]));
                        M_2 = string(abi.encodePacked(M_2,Ls2[4],Ls2[5],Ls2[6]));
                    }else{M_2 = string(abi.encodePacked(M_2,' '));}
                }else{M_2 = string(abi.encodePacked(M_2,Ls2[0],Ls2[1],Ls2[2],Ls2[3]));
                 M_2 = string(abi.encodePacked(M_2,Ls2[4],Ls2[5],Ls2[6]));}
            }else if(i>20){
                Ls2[5] = size[y];
                if(i==22){
                    if(getAttr1(tokenId)){
                        M_3 = string(abi.encodePacked(M_3,Ls2[0],Ls2[1],Ls2[2],Ls2[3]));
                        M_3 = string(abi.encodePacked(M_3,Ls2[4],Ls2[5],Ls2[6]));
                    }else{M_3 = string(abi.encodePacked(M_3,' '));}
                }else if(i==27){
                    if(getAttr3(tokenId)){
                        M_3 = string(abi.encodePacked(M_3,Ls2[0],Ls2[1],Ls2[2],Ls2[3]));
                        M_3 = string(abi.encodePacked(M_3,Ls2[4],Ls2[5],Ls2[6]));
                    }else{M_3 = string(abi.encodePacked(M_3,' '));}
                }else if(i==28){
                    if(getAttr2(tokenId)){
                        M_3 = string(abi.encodePacked(M_3,Ls2[0],Ls2[1],Ls2[2],Ls2[3]));
                        M_3 = string(abi.encodePacked(M_3,Ls2[4],Ls2[5],Ls2[6]));
                    }else{M_3 = string(abi.encodePacked(M_3,' '));}
                }else{  M_3 = string(abi.encodePacked(M_3,Ls2[0],Ls2[1],Ls2[2],Ls2[3]));
                        M_3 = string(abi.encodePacked(M_3,Ls2[4],Ls2[5],Ls2[6]));}
                y+=1;  
            }
            if (i==20){
                L_1 = string(abi.encodePacked(Ls3[0],"wj",Ls3[1],M_2,Ls3[2],sports[0],Ls3[3],"wj",Ls3[4]));
            }
            if(i==35){
                L_2 = string(abi.encodePacked(Ls3[0],"cQ",Ls3[1],M_3,Ls3[2],sports[1],Ls3[3],"cQ",Ls3[4]));
                L_3 = string(abi.encodePacked(Ls1[0],Ls1[1],Ls1[2],Ls1[3]));
                L_3 = string(abi.encodePacked(L_3,Ls1[4],M_1,L_1,L_2,Ls3[5]));
            }
        }
        return string(abi.encodePacked("Copy the following content into the HTML file and open it for viewing:,",L_3));
    }
}

