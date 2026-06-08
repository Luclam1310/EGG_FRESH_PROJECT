
module cycle_timer#(
    parameter BIT_WIDTH = 16
)(
    input   wire                            clock,
    input   wire                            reset_n,
    input   wire                            enable,
    input   wire                            load_count,
    input   wire    [BIT_WIDTH-1:0]         count,

    output  logic                           expired
);


reg     [BIT_WIDTH-1:0] counter;
logic   [BIT_WIDTH-1:0] _counter;

always_comb begin
    _counter    =   counter;

    if (counter == 0) begin
        expired = 1;
    end
    else begin
        expired = 0;
    end

    if (enable) begin
        if (load_count) begin
            _counter = count;
        end
        else begin
            if (counter == 0) begin
            end
            else begin
                _counter    = counter - 1;
            end
        end
    end
end


always_ff @(posedge clock or negedge reset_n) begin
    if (!reset_n) begin
        counter <=  '1;
    end
    else begin
        counter <=  _counter;
    end
end

endmodule