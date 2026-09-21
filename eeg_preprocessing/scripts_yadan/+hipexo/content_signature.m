function signature = content_signature(value)
% Hash complete values and array dimensions with SHA-256, without sampling.
% Single/double storage of identical values has the same identity.
digest = java.security.MessageDigest.getInstance('SHA-256');
write_value(value);
hashBytes = typecast(digest.digest(), 'uint8');
signature = "content-sha256:" + string(lower(reshape(dec2hex(hashBytes, 2).', 1, [])));

    function write_value(v)
        if istable(v), v = table2struct(v); end
        if isa(v, 'datetime')
            put_text('datetime'); write_value(posixtime(v)); put_text(v.TimeZone); return;
        elseif isa(v, 'duration')
            put_text('duration'); write_value(seconds(v)); return;
        elseif iscategorical(v)
            put_text('categorical'); write_value(string(v));
            write_value(string(categories(v))); write_value(isordinal(v)); return;
        end
        if ischar(v), v = string(v); end
        if isstruct(v)
            put_text('struct'); put_size(size(v));
            names = sort(fieldnames(v));
            put_size(numel(names));
            for n = 1:numel(names), put_text(names{n}); end
            for k = 1:numel(v)
                for n = 1:numel(names), write_value(v(k).(names{n})); end
            end
        elseif iscell(v)
            put_text('cell'); put_size(size(v));
            for k = 1:numel(v), write_value(v{k}); end
        elseif isstring(v)
            put_text('text'); put_size(size(v));
            for k = 1:numel(v)
                put_size(ismissing(v(k)));
                if ~ismissing(v(k)), put_text(char(v(k))); end
            end
        elseif isnumeric(v) || islogical(v)
            if isfloat(v), numericClass = 'double'; else, numericClass = class(v); end
            put_text(numericClass); put_size(size(v)); put_size(~isreal(v));
            % I/O buffer size only; this is not an analysis threshold.
            blockElements = 2^18;
            for part = 1:(1 + ~isreal(v))
                for first = 1:blockElements:numel(v)
                    last = min(numel(v), first + blockElements - 1);
                    if part == 1, block = real(v(first:last)); else, block = imag(v(first:last)); end
                    block = full(block(:));
                    if isfloat(block)
                        block = double(block);
                        block(isnan(block)) = NaN;
                        block(block == 0) = 0;
                    elseif islogical(block)
                        block = uint8(block);
                    end
                    digest.update(typecast(block, 'int8'));
                end
            end
        else
            error('Content signature does not support %s.', class(v));
        end
    end

    function put_size(dimensions)
        numbers = uint64([numel(dimensions), double(dimensions(:)')]);
        digest.update(typecast(numbers(:), 'int8'));
    end

    function put_text(txt)
        bytes = unicode2native(txt, 'UTF-8');
        put_size(numel(bytes));
        if ~isempty(bytes), digest.update(typecast(uint8(bytes(:)), 'int8')); end
    end
end
