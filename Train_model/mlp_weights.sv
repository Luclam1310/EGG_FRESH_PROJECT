package mlp_weights_pkg;

  // Mean của kênh raw (R,S,T,U,V,W) — Q8 format: mean * 256
  // QUAN TRỌNG: dùng *256 để giữ precision (ví dụ mean=0.5 → 128)
  parameter int SCALER_MEAN_RAW [0:5] = '{
    0, 18030, 11536, 5972, 3054, 0
  };

  // Mean của kênh ratio — Q16 format: mean * 65536
  parameter int SCALER_MEAN_RATIO [0:5] = '{
    0, 30686, 19602, 10092, 5156, 0
  };

  // Nghịch đảo std-dev — Q16 format: 65536 / std
  parameter int SCALER_STD_INV [0:11] = '{
    65536, 3745, 5687, 10150, 19375, 65536, 65536, 3482162, 4224272, 6884889, 11063100, 65536
  };

  // Layer 0: (12, 16)
  // W: signed [15:0] — Q8 (float * 256)
  // B: signed [31:0] — Q16 (float * 65536)
  parameter signed [15:0] W1 [11:0][15:0] = '{
    {16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000},
    {16'sh0014, 16'shFFFE, 16'shFFC9, 16'shFFBF, 16'shFFC7, 16'shFF97, 16'shFF9A, 16'shFFB7, 16'shFFDC, 16'shFFA1, 16'shFFDA, 16'shFFAE, 16'sh0035, 16'shFF47, 16'shFFEB, 16'shFFEC},
    {16'shFFD3, 16'sh006E, 16'sh004E, 16'sh008C, 16'shFF8B, 16'shFF6A, 16'shFFF1, 16'shFFCB, 16'shFF8D, 16'shFF6F, 16'shFFB6, 16'shFFF7, 16'shFFCC, 16'shFFC4, 16'shFFA0, 16'sh0027},
    {16'sh003C, 16'shFFB7, 16'sh003E, 16'sh009A, 16'sh0025, 16'sh0035, 16'shFFD7, 16'sh0031, 16'shFF7B, 16'shFF6C, 16'shFFBC, 16'shFF80, 16'shFFDD, 16'shFF64, 16'sh001E, 16'sh0025},
    {16'sh000B, 16'sh002E, 16'shFFB7, 16'sh006E, 16'shFF5E, 16'sh004C, 16'sh0020, 16'shFF96, 16'shFF68, 16'shFFEE, 16'sh001B, 16'shFFF0, 16'sh0074, 16'shFF43, 16'shFFAA, 16'shFFAD},
    {16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000},
    {16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000},
    {16'sh0041, 16'shFFF9, 16'sh000D, 16'shFFC2, 16'sh004A, 16'shFFD3, 16'sh005D, 16'sh0005, 16'sh0058, 16'sh0051, 16'shFFA0, 16'shFF8B, 16'shFFD3, 16'sh0004, 16'sh0050, 16'sh0083},
    {16'shFFB2, 16'sh0034, 16'shFFB9, 16'sh0025, 16'shFF82, 16'shFF94, 16'sh0062, 16'shFFB3, 16'sh0068, 16'sh002F, 16'shFFD4, 16'sh0097, 16'sh0058, 16'shFFBF, 16'shFFDB, 16'shFF80},
    {16'shFFFA, 16'shFFDA, 16'sh0050, 16'sh008D, 16'shFF9E, 16'sh0001, 16'sh006E, 16'shFFDA, 16'shFF68, 16'sh0019, 16'sh011B, 16'shFFB1, 16'sh002D, 16'sh0031, 16'shFFD4, 16'sh0068},
    {16'shFFF5, 16'sh0043, 16'sh0033, 16'sh0098, 16'shFFA7, 16'sh0022, 16'shFFE8, 16'shFFC2, 16'shFF58, 16'shFFF1, 16'shFFE1, 16'shFF93, 16'sh003E, 16'shFFA7, 16'shFFFF, 16'shFF75},
    {16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000, 16'sh0000}
  };

  parameter signed [31:0] B1 [15:0] = '{
    32'sh00007792, 32'sh0000DE99, 32'sh0000D5D9, 32'shFFFF28F7, 32'sh00006988, 32'sh00011CDD, 32'sh0000DEDF, 32'sh0000E19B, 32'sh00004FFD, 32'shFFFE2CA0, 32'sh00003D08, 32'sh0000C07E, 32'sh0000DF2A, 32'shFFFFE26D, 32'sh00002F92, 32'sh00004FCD
  };

  // Layer 1: (16, 8)
  // W: signed [15:0] — Q8 (float * 256)
  // B: signed [31:0] — Q16 (float * 65536)
  parameter signed [15:0] W2 [15:0][7:0] = '{
    {16'shFF6E, 16'shFFE0, 16'sh0048, 16'sh001B, 16'shFFE0, 16'shFFF3, 16'sh0090, 16'shFFE3},
    {16'shFFCB, 16'sh00AB, 16'sh0081, 16'sh00C0, 16'sh0026, 16'sh0067, 16'sh0023, 16'sh0030},
    {16'shFFF2, 16'sh002D, 16'sh00E6, 16'shFEE2, 16'sh0075, 16'sh00AA, 16'sh00D4, 16'sh007E},
    {16'shFFEA, 16'shFF91, 16'shFF07, 16'shFFB2, 16'shFFB2, 16'shFEDC, 16'shFF56, 16'shFF38},
    {16'sh0042, 16'sh0099, 16'sh008F, 16'shFFE2, 16'shFF32, 16'sh0097, 16'sh001A, 16'sh009D},
    {16'sh0068, 16'sh00D1, 16'sh004C, 16'shFF20, 16'sh007E, 16'sh0052, 16'sh004B, 16'sh0087},
    {16'sh0058, 16'sh008C, 16'sh006D, 16'shFF94, 16'sh0008, 16'sh00E2, 16'sh001E, 16'sh0060},
    {16'sh004B, 16'sh008D, 16'sh0082, 16'sh000C, 16'shFF0A, 16'sh0023, 16'sh00BB, 16'sh0099},
    {16'sh003D, 16'sh0092, 16'sh002C, 16'sh0008, 16'sh0035, 16'sh0055, 16'sh0064, 16'sh0074},
    {16'shFECA, 16'shFE65, 16'shFE6F, 16'shFF8E, 16'sh001A, 16'shFE0E, 16'shFE54, 16'shFEA5},
    {16'shFFCA, 16'sh0066, 16'shFFDF, 16'shFF84, 16'sh0077, 16'sh003D, 16'sh000D, 16'sh005A},
    {16'sh0023, 16'shFFE9, 16'sh0052, 16'shFFB7, 16'shFEC8, 16'sh003F, 16'sh004F, 16'sh005A},
    {16'sh004E, 16'sh0102, 16'sh0084, 16'sh009D, 16'sh0046, 16'sh0059, 16'sh00B6, 16'sh0032},
    {16'shFF69, 16'sh00C5, 16'sh00A6, 16'sh002A, 16'shFFA2, 16'sh0004, 16'sh000C, 16'sh000D},
    {16'shFFB0, 16'sh004E, 16'sh0040, 16'shFFB7, 16'sh0013, 16'sh0054, 16'sh001E, 16'sh0037},
    {16'shFFC2, 16'shFF9E, 16'shFFB9, 16'sh002F, 16'shFF61, 16'shFF6B, 16'shFF26, 16'shFF57}
  };

  parameter signed [31:0] B2 [7:0] = '{
    32'sh00004AF5, 32'sh00008879, 32'sh00004DA4, 32'shFFFFB1FE, 32'shFFFFFE8D, 32'sh00005AC6, 32'sh000033AC, 32'sh00003EDE
  };

  // Layer 2: (8, 1)
  // W: signed [15:0] — Q8 (float * 256)
  // B: signed [31:0] — Q16 (float * 65536)
  parameter signed [15:0] W3 [7:0][0:0] = '{
    {16'sh001D},
    {16'sh0089},
    {16'sh0097},
    {16'shFE62},
    {16'shFF17},
    {16'sh00AA},
    {16'sh0088},
    {16'sh00F5}
  };

  parameter signed [31:0] B3 [0:0] = '{
    32'sh0000826E
  };

endpackage
