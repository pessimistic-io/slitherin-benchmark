/**
 *Submitted for verification at Etherscan.io on 2022-06-21
*/

pragma solidity 0.8.0;

contract testApp {

    uint256 first;
    uint256 second;

    function returnMeSingle() public pure returns (string memory) {
        return "data:application/json;base64,eyJuYW1lIjogIk9uQ2hhaW4gRHVkZSAjMCIsICJhdHRyaWJ1dGVzIjogW3sidHJhaXRfdHlwZSI6ICJCYWNrZ3JvdW5kIiwidmFsdWUiOiAiMiJ9LHsidHJhaXRfdHlwZSI6ICJTa2luIiwidmFsdWUiOiAiOCJ9LHsidHJhaXRfdHlwZSI6ICJFYXJyaW5nIiwidmFsdWUiOiAiMCJ9LHsidHJhaXRfdHlwZSI6ICJIYXQiLCJ2YWx1ZSI6ICI5In0seyJ0cmFpdF90eXBlIjogIkV5ZXMiLCJ2YWx1ZSI6ICIwIn1dLCJpbWFnZSI6ICJkYXRhOmltYWdlL3N2Zyt4bWw7YmFzZTY0LFBITjJaeUI0Yld4dWN6MGlhSFIwY0RvdkwzZDNkeTUzTXk1dmNtY3ZNakF3TUM5emRtY2lJSEJ5WlhObGNuWmxRWE53WldOMFVtRjBhVzg5SW5oTmFXNVpUV2x1SUcxbFpYUWlJSFpwWlhkQ2IzZzlJakFnTUNBMU1EQWdOVEF3SWo0OGNtRmthV0ZzUjNKaFpHbGxiblFnYVdROUltZHlZV1F4SWlCamVEMGlOVEFsSWlCamVUMGlOVEFsSWlCeVBTSTFNQ1VpSUdaNFBTSTFNQ1VpSUdaNVBTSTFNQ1VpUGp4emRHOXdJRzltWm5ObGREMGlNU1VpSUhOMGVXeGxQU0p6ZEc5d0xXTnZiRzl5T2lObFpXVTdjM1J2Y0MxdmNHRmphWFI1T2pFaUlDOCtQSE4wYjNBZ2IyWm1jMlYwUFNJeE1EQWxJaUJ6ZEhsc1pUMGljM1J2Y0MxdmNHRmphWFI1T2pFN2MzUnZjQzFqYjJ4dmNqb2paVGt5SWk4K1BDOXlZV1JwWVd4SGNtRmthV1Z1ZEQ0OGNtVmpkQ0I0UFNJd0lpQjVQU0l3SWlCM2FXUjBhRDBpTlRBd0lpQm9aV2xuYUhROUlqVXdNQ0lnYzNSNWJHVTlJbVpwYkd3NmRYSnNLQ05uY21Ga01Ta2lMejQ4Y21WamRDQjNhV1IwYUQwaU1DSWdhR1ZwWjJoMFBTSXdJaUI0UFNJNU9TSWdlVDBpTkRBd0lpQnpkSGxzWlQwaVptbHNiRG9qTmpVeklpOCtQR05wY21Oc1pTQmplRDBpTVRrd0lpQmplVDBpTkRjd0lpQnlQU0l3SWlCemRIbHNaVDBpWm1sc2JEb2pNRFE1SWk4K1BHTnBjbU5zWlNCamVEMGlNekV3SWlCamVUMGlORGN3SWlCeVBTSXdJaUJ6ZEhsc1pUMGlabWxzYkRvak1EUTVJaTgrUEdOcGNtTnNaU0JqZUQwaU1UVXdJaUJqZVQwaU1qVXdJaUJ5UFNJMU1DSWdjM1I1YkdVOUltWnBiR3c2SXpZMU15SXZQanhqYVhKamJHVWdZM2c5SWpFMU1DSWdZM2s5SWpJMU1DSWdjajBpTkRBaUlITjBlV3hsUFNKbWFXeHNPaU13TkRraUx6NDhZMmx5WTJ4bElHTjRQU0l6TlRBaUlHTjVQU0l5TlRBaUlISTlJalV3SWlCemRIbHNaVDBpWm1sc2JEb2pOalV6SWk4K1BHTnBjbU5zWlNCamVEMGlNelV3SWlCamVUMGlNalV3SWlCeVBTSTBNQ0lnYzNSNWJHVTlJbVpwYkd3Nkl6QTBPU0l2UGp4eVpXTjBJSGc5SWpFMU1DSWdlVDBpTVRBd0lpQWdkMmxrZEdnOUlqSXdNQ0lnYUdWcFoyaDBQU0l6TURBaUlISjRQU0l4TUNJZ2NuazlJakV3SWlCemRIbHNaVDBpWm1sc2JEb2pOalV6SWk4K1BISmxZM1FnZUQwaU1UWXdJaUI1UFNJeE1UQWlJQ0IzYVdSMGFEMGlNVGd3SWlCb1pXbG5hSFE5SWpJNE1DSWdjbmc5SWpFd0lpQnllVDBpTVRBaUlITjBlV3hsUFNKbWFXeHNPaU13TkRraUx6NDhZMmx5WTJ4bElHTjRQU0l5TURBaUlHTjVQU0l5TVRVaUlISTlJak0xSWlCemRIbHNaVDBpWm1sc2JEb2pabVptSWk4K1BHTnBjbU5zWlNCamVEMGlNekExSWlCamVUMGlNakl5SWlCeVBTSXpNU0lnYzNSNWJHVTlJbVpwYkd3NkkyWm1aaUl2UGp4amFYSmpiR1VnWTNnOUlqSXdNQ0lnWTNrOUlqSXlNQ0lnY2owaU1qQWlJSE4wZVd4bFBTSm1hV3hzT2lOaFltVWlMejQ4WTJseVkyeGxJR040UFNJek1EQWlJR041UFNJeU1qQWlJSEk5SWpJd0lpQnpkSGxzWlQwaVptbHNiRG9qWVdKbElpOCtQR05wY21Oc1pTQmplRDBpTWpBd0lpQmplVDBpTWpJd0lpQnlQU0kzSWlCemRIbHNaVDBpWm1sc2JEb2pNREF3SWk4K1BHTnBjbU5zWlNCamVEMGlNekF3SWlCamVUMGlNakl3SWlCeVBTSTNJaUJ6ZEhsc1pUMGlabWxzYkRvak1EQXdJaTgrUEdWc2JHbHdjMlVnWTNnOUlqSTFNQ0lnWTNrOUlqTXhOU0lnY25nOUlqQWlJSEo1UFNJd0lpQnpkSGxzWlQwaVptbHNiRG9qWm1aaklpOCtQR05wY21Oc1pTQmplRDBpTWpZNElpQmplVDBpTWprMUlpQnlQU0kxSWlCemRIbHNaVDBpWm1sc2JEb2pNREF3SWk4K1BHTnBjbU5zWlNCamVEMGlNak15SWlCamVUMGlNamsxSWlCeVBTSTFJaUJ6ZEhsc1pUMGlabWxzYkRvak1EQXdJaTgrUEhKbFkzUWdlRDBpTVRrMUlpQjVQU0l6TXpBaUlIZHBaSFJvUFNJeE1UQWlJR2hsYVdkb2REMGlPQ0lnYzNSNWJHVTlJbVpwYkd3Nkl6QXdNQ0l2UGp4eVpXTjBJSGRwWkhSb1BTSXlNREFpSUdobGFXZG9kRDBpT1RraUlIZzlJakUxTUNJZ2VUMGlOREFpSUhKNVBTSXlNQ0lnYzNSNWJHVTlJbVpwYkd3Nkl6QXdaaUl2UGp4eVpXTjBJSGRwWkhSb1BTSXlOekFpSUdobGFXZG9kRDBpTXpNaUlIZzlJakUxTUNJZ2VUMGlNVEEySWlCeWVUMGlOU0lnYzNSNWJHVTlJbVpwYkd3Nkl6Qm1NQ0l2UGp4eVpXTjBJSGRwWkhSb1BTSTRNQ0lnYUdWcFoyaDBQU0l4TWpBaUlIZzlJakl4TUNJZ2VUMGlOREF3SWlCemRIbHNaVDBpWm1sc2JEb2pOalV6SWk4K1BISmxZM1FnZDJsa2RHZzlJall3SWlCb1pXbG5hSFE5SWpFeU1DSWdlRDBpTWpJd0lpQjVQU0kwTURBaUlITjBlV3hsUFNKbWFXeHNPaU13TkRraUx6NDhMM04yWno0PSJ9";
    }

    function returnMeDouble() public pure returns (string memory) {
        return "HERE I AM WITH ANOTHER TEST CASE BUT THIS ONE IS A LOT LONGER AND MAY CAUSE PROBLEMS WITH A MERE 64 HEX-BYTE CHARACTER.";
    }

    function returnMeSingleTrigger() public returns (string memory) {
        first = first + 1;
        return "HERE I AM WITH A TEST CASE";
    }

    function returnMeDoubleTrigger() public returns (string memory) {
        second = second + 1;
        return "HERE I AM WITH ANOTHER TEST CASE BUT THIS ONE IS A LOT LONGER AND MAY CAUSE PROBLEMS WITH A MERE 64 HEX-BYTE CHARACTER.";
    }

    function test() public pure returns (string[3] memory) {
        return ["aaa","bbbb","HERE I AM WITH ANOTHER TEST CASE BUT THIS ONE IS A LOT LONGER AND MAY CAUSE PROBLEMS WITH A MERE 64 HEX-BYTE CHARACTER."];
    }

    function testByte() public pure returns (bytes memory) {
        uint8 u8 = 1;
        bytes memory bts = new bytes(32);
        bytes32 b32 = "Terry A. Davis";
        assembly {
            mstore(add(bts, /*BYTES_HEADER_SIZE*/32), u8)
            mstore(add(bts, /*BYTES_HEADER_SIZE*/32), b32)
        }
        return bts;
    }

  function testFixByte() public pure returns (bytes[2] memory) {
     bytes memory a = abi.encodePacked(uint256(123));
        bytes memory b = abi.encodePacked(uint256(456));
        return [a,b];
    }

    function name() public view returns (string memory){
        return "\"><script>alert(/xss/)</script>";
    }

}