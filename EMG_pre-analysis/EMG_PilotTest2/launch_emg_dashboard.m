%% Dashboard GUI Local Function 
function launch_emg_dashboard(session_names, session_data_cell, session_edges_cell, muscle_names)
    f = figure('Name', 'Interactive Multi-Session EMG Dashboard', ...
               'Position', [100, 100, 1400, 800], 'Color', 'w', ...
               'NumberTitle', 'off', 'MenuBar', 'none');

    uicontrol('Style', 'text', 'String', 'Select Session:', ...
              'Position', [20, 750, 120, 20], 'BackgroundColor', 'w', ...
              'FontSize', 12, 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
          
    popup_session = uicontrol('Style', 'popupmenu', ...
                              'String', session_names, ...
                              'Position', [140, 750, 200, 25], ...
                              'FontSize', 12);

    num_muscles = length(muscle_names);
    plots_per_page = 6; 
    num_pages = ceil(num_muscles / plots_per_page);
    
    page_strings = cell(1, num_pages);
    for p = 1:num_pages
        start_m = (p-1)*plots_per_page + 1;
        end_m = min(p*plots_per_page, num_muscles);
        page_strings{p} = sprintf('Page %d (Muscle %d-%d)', p, start_m, end_m);
    end

    uicontrol('Style', 'text', 'String', 'Select Muscle Group (Page):', ...
              'Position', [400, 750, 220, 20], 'BackgroundColor', 'w', ...
              'FontSize', 12, 'HorizontalAlignment', 'left', 'FontWeight', 'bold');
          
    popup_page = uicontrol('Style', 'popupmenu', ...
                           'String', page_strings, ...
                           'Position', [630, 750, 250, 25], ...
                           'FontSize', 12);

    ax = gobjects(1, plots_per_page);
    for i = 1:plots_per_page
        col_idx = floor((i-1)/2); 
        row_idx = mod(i-1, 2);    
        ax(i) = axes('Parent', f, 'Position', ...
            [0.05 + col_idx*0.32,  0.52 - row_idx*0.42,  0.27,  0.35]);
    end

    set(popup_session, 'Callback', @(src, event) update_plots());
    set(popup_page,    'Callback', @(src, event) update_plots());

    update_plots();

    function update_plots()
        sess_idx = popup_session.Value;
        page_idx = popup_page.Value;

        curr_data  = session_data_cell{sess_idx};
        curr_edges = session_edges_cell{sess_idx};
        
        if isempty(curr_data) || size(curr_data, 1) == 0
            for k = 1:plots_per_page
                cla(ax(k)); set(ax(k), 'Visible', 'off');
            end
            title(ax(1), 'No valid data for this Session', 'Color', 'r', 'Visible', 'on');
            return;
        end

        actual_length = size(curr_data, 2); 
        gait_percent = linspace(0, 100, actual_length);
        
        start_m = (page_idx-1)*plots_per_page + 1;
        end_m   = min(page_idx*plots_per_page, num_muscles);
        muscles_to_plot = start_m:end_m;
        event_labels = {'LTO', 'LHS', 'RTO'};

        for k = 1:plots_per_page
            cla(ax(k)); 
            
            if k <= length(muscles_to_plot)
                m_idx = muscles_to_plot(k);
                
                % Safely calculate mean and std by omitting NaNs
                mean_profile = reshape(mean(curr_data(:, :, m_idx), 1, 'omitnan'), 1, []);
                std_profile  = reshape(std(curr_data(:, :, m_idx), 0, 1, 'omitnan'), 1, []);
                
                % Check if the channel is completely missing (all NaNs)
                if all(isnan(mean_profile))
                    title(ax(k), [strrep(muscle_names{m_idx}, '_', '\_'), ' (No Data)'], ...
                          'Color', 'r', 'FontSize', 12, 'FontWeight', 'bold');
                    set(ax(k), 'Visible', 'on');
                    set(ax(k), 'XTick', [], 'YTick', []); % Clear axes for empty plot
                    box(ax(k), 'on');
                    continue;
                end

                hold(ax(k), 'on');
                
                fill(ax(k), [gait_percent, fliplr(gait_percent)], ...
                     [mean_profile + std_profile, fliplr(mean_profile - std_profile)], ...
                     [0.8 0.8 1], 'EdgeColor', 'none', 'FaceAlpha', 0.5);

                plot(ax(k), gait_percent, mean_profile, 'b', 'LineWidth', 2);

                for ed = 1:3
                    xline(ax(k), curr_edges(ed), '--r', event_labels{ed}, ...
                        'LabelVerticalAlignment', 'top', ...
                        'LabelHorizontalAlignment', 'center', ...
                        'LineWidth', 1.5);
                end

                title(ax(k), strrep(muscle_names{m_idx}, '_', '\_'), ...
                      'FontSize', 12, 'FontWeight', 'bold');
                xlabel(ax(k), 'Gait Cycle (%)');
                ylabel(ax(k), 'EMG (\muV)');
                xlim(ax(k), [0 100]);
                grid(ax(k), 'on');
                set(ax(k), 'Visible', 'on');
                hold(ax(k), 'off');
            else
                set(ax(k), 'Visible', 'off'); 
            end
        end
    end
end