% GOAL
%   Return the representative DIPFIT coordinate used in the manual IC
%   review workbook.
%
% METHOD
%   Preserve the current review-workbook rule exactly: use the only valid
%   dipole when one exists; for multiple valid dipoles, select the dipole
%   with the largest finite moment norm when compatible momxyz data exist;
%   otherwise use the first valid dipole.

function xyz = representative_dipole_xyz(model)

    xyz = [NaN NaN NaN];

    positions = double(model.posxyz);

    if isvector(positions) && numel(positions) == 3
        positions = reshape(positions, 1, 3);
    elseif size(positions, 2) ~= 3 && size(positions, 1) == 3
        positions = positions';
    end

    if size(positions, 2) ~= 3
        return;
    end

    finitePosition = all(isfinite(positions), 2);

    if ~any(finitePosition)
        return;
    end

    originalRowIndices = find(finitePosition);
    positions = positions(finitePosition, :);
    selectedRow = 1;

    if size(positions, 1) > 1 && ...
            isfield(model, 'momxyz') && ~isempty(model.momxyz)

        moments = double(model.momxyz);

        if isvector(moments) && numel(moments) == 3
            moments = reshape(moments, 1, 3);
        elseif size(moments, 2) ~= 3 && size(moments, 1) == 3
            moments = moments';
        end

        if size(moments, 2) == 3 && ...
                size(moments, 1) >= max(originalRowIndices)

            momentNorm = sqrt(sum( ...
                moments(originalRowIndices, :) .^ 2, 2));
            momentNorm(~isfinite(momentNorm)) = -Inf;

            if any(isfinite(momentNorm))
                [~, selectedRow] = max(momentNorm);
            end
        end
    end

    xyz = positions(selectedRow, :);
end


